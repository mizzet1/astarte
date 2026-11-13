#
# This file is part of Astarte.
#
# Copyright 2025 SECO Mind Srl
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# SPDX-License-Identifier: Apache-2.0
#

defmodule Astarte.DataUpdaterPlant.DataUpdater.Core.Device do
  @moduledoc """
  Core part of the data_updater message processing.

  This module contains functions and utilities to process devices.
  """

  alias Astarte.Core.CQLUtils
  alias Astarte.Core.Device
  alias Astarte.Core.InterfaceDescriptor
  alias Astarte.Core.Mapping
  alias Astarte.DataUpdaterPlant.Config
  alias Astarte.DataUpdaterPlant.DataUpdater.Cache
  alias Astarte.DataUpdaterPlant.DataUpdater.Core
  alias Astarte.DataUpdaterPlant.DataUpdater.Core.KeyAgreement.HandshakeState
  alias Astarte.DataUpdaterPlant.DataUpdater.PayloadsDecoder
  alias Astarte.DataUpdaterPlant.DataUpdater.Queries
  alias Astarte.DataUpdaterPlant.DataUpdater.State
  alias Astarte.DataUpdaterPlant.RPC.VMQPlugin
  alias Astarte.DataUpdaterPlant.TimeBasedActions
  alias Astarte.DataUpdaterPlant.TriggersHandler
  alias Astarte.Secrets
  alias Astarte.Secrets.EncryptedMessages

  require Logger

  def process_introspection(state, new_introspection_list, payload, timestamp) do
    new_state = TimeBasedActions.execute_time_based_actions(state, timestamp)

    timestamp_ms = div(timestamp, 10_000)

    {db_introspection_map, db_introspection_minor_map} =
      List.foldl(new_introspection_list, {%{}, %{}}, fn {interface, major, minor},
                                                        {introspection_map,
                                                         introspection_minor_map} ->
        introspection_map = Map.put(introspection_map, interface, major)
        introspection_minor_map = Map.put(introspection_minor_map, interface, minor)

        {introspection_map, introspection_minor_map}
      end)

    realm = new_state.realm
    device_id = new_state.device_id
    groups = new_state.groups

    TriggersHandler.incoming_introspection(
      realm,
      device_id,
      groups,
      payload,
      timestamp_ms
    )

    # TODO: implement here object_id handling for a certain interface name. idea: introduce
    # interface_family_id

    current_sorted_introspection =
      new_state.introspection
      |> Enum.map(fn x -> x end)
      |> Enum.sort()

    new_sorted_introspection =
      db_introspection_map
      |> Enum.map(fn x -> x end)
      |> Enum.sort()

    diff = List.myers_difference(current_sorted_introspection, new_sorted_introspection)

    handle_introspection_diff(
      diff,
      realm,
      device_id,
      groups,
      state.device_id,
      db_introspection_minor_map,
      timestamp_ms
    )

    {added_interfaces, removed_interfaces} =
      Enum.reduce(diff, {%{}, %{}}, fn {change_type, changed_interfaces}, {add_acc, rm_acc} ->
        case change_type do
          :ins ->
            changed_map = Enum.into(changed_interfaces, %{})
            {Map.merge(add_acc, changed_map), rm_acc}

          :del ->
            changed_map = Enum.into(changed_interfaces, %{})
            {add_acc, Map.merge(rm_acc, changed_map)}

          :eq ->
            {add_acc, rm_acc}
        end
      end)

    # TODO this could be a bang!
    {:ok, old_minors} = Queries.fetch_device_introspection_minors(state.realm, state.device_id)

    readded_introspection = Enum.to_list(added_interfaces)

    old_introspection =
      Enum.reduce(removed_interfaces, %{}, fn {iface, _major}, acc ->
        prev_major = Map.fetch!(state.introspection, iface)
        prev_minor = Map.get(old_minors, iface, 0)
        Map.put(acc, {iface, prev_major}, prev_minor)
      end)

    :ok = Queries.add_old_interfaces(realm, new_state.device_id, old_introspection)
    :ok = Queries.remove_old_interfaces(realm, new_state.device_id, readded_introspection)

    maybe_deliver_interface_minor_updated_triggers(
      new_state,
      db_introspection_map,
      db_introspection_minor_map,
      old_minors,
      timestamp_ms
    )

    # Removed/updated interfaces must be purged away, otherwise data will be written using old
    # interface_id.
    remove_interfaces_list = Map.keys(removed_interfaces)

    {interfaces_to_drop_map, _} = Map.split(new_state.interfaces, remove_interfaces_list)
    interfaces_to_drop_list = Map.keys(interfaces_to_drop_map)

    # Forget interfaces wants a list of already loaded interfaces, otherwise it will crash
    new_state = Core.Interface.forget_interfaces(new_state, interfaces_to_drop_list)

    Queries.update_device_introspection!(
      realm,
      new_state.device_id,
      db_introspection_map,
      db_introspection_minor_map
    )

    :telemetry.execute(
      [:astarte, :data_updater_plant, :data_updater, :processed_introspection],
      %{},
      %{realm: realm}
    )

    final_state = %{
      new_state
      | introspection: db_introspection_map,
        paths_cache: Cache.new(Config.paths_cache_size!()),
        total_received_msgs: new_state.total_received_msgs + 1,
        total_received_bytes: new_state.total_received_bytes + byte_size(payload)
    }

    {:ack, :ok, final_state}
  end

  defp handle_introspection_diff(
         diff,
         realm,
         device_id,
         groups,
         device_db_id,
         db_introspection_minor_map,
         timestamp_ms
       ) do
    Enum.each(diff, fn {change_type, changed_interfaces} ->
      handle_introspection_change(
        change_type,
        changed_interfaces,
        realm,
        device_id,
        groups,
        device_db_id,
        db_introspection_minor_map,
        timestamp_ms
      )
    end)
  end

  defp handle_introspection_change(
         :ins,
         changed_interfaces,
         realm,
         device_id,
         groups,
         device_db_id,
         db_introspection_minor_map,
         timestamp_ms
       ) do
    Logger.debug("Adding interfaces to introspection: #{inspect(changed_interfaces)}.")

    Enum.each(changed_interfaces, fn {interface_name, interface_major} ->
      maybe_register_interface(realm, device_db_id, interface_name, interface_major)

      minor = Map.get(db_introspection_minor_map, interface_name)

      TriggersHandler.interface_added(
        realm,
        device_id,
        groups,
        interface_name,
        interface_major,
        minor,
        timestamp_ms
      )
    end)
  end

  defp handle_introspection_change(
         :del,
         changed_interfaces,
         realm,
         device_id,
         groups,
         device_db_id,
         _db_introspection_minor_map,
         timestamp_ms
       ) do
    Logger.debug("Removing interfaces from introspection: #{inspect(changed_interfaces)}.")

    Enum.each(changed_interfaces, fn {interface_name, interface_major} ->
      maybe_unregister_interface(realm, device_db_id, interface_name, interface_major)

      TriggersHandler.interface_removed(
        realm,
        device_id,
        groups,
        interface_name,
        interface_major,
        timestamp_ms
      )
    end)
  end

  defp handle_introspection_change(
         :eq,
         changed_interfaces,
         _realm,
         _device_id,
         _groups,
         _device_db_id,
         _db_introspection_minor_map,
         _timestamp_ms
       ) do
    Logger.debug("#{inspect(changed_interfaces)} are already on device introspection.")
  end

  defp maybe_register_interface(realm, device_db_id, interface_name, interface_major)
       when interface_major == 0 do
    Queries.register_device_with_interface(realm, device_db_id, interface_name, 0)
  end

  defp maybe_register_interface(_realm, _device_db_id, _interface_name, _interface_major),
    do: :ok

  defp maybe_unregister_interface(realm, device_db_id, interface_name, interface_major)
       when interface_major == 0 do
    Queries.unregister_device_with_interface(realm, device_db_id, interface_name, 0)
  end

  defp maybe_unregister_interface(_realm, _device_db_id, _interface_name, _interface_major),
    do: :ok

  defp maybe_deliver_interface_minor_updated_triggers(
         state,
         db_introspection_map,
         db_introspection_minor_map,
         old_minors,
         timestamp_ms
       ) do
    for {interface_name, old_minor} <- old_minors do
      with {:ok, interface_major} <-
             major_in_introspection?(state, db_introspection_map, interface_name),
           {:ok, new_minor} <-
             new_minor_different?(db_introspection_minor_map, interface_name, old_minor) do
        TriggersHandler.interface_minor_updated(
          state.realm,
          state.device_id,
          state.groups,
          interface_name,
          interface_major,
          old_minor,
          new_minor,
          timestamp_ms
        )
      end
    end
  end

  defp major_in_introspection?(
         %State{introspection: introspection},
         db_introspection_map,
         interface_name
       ) do
    with {:ok, interface_major} <- Map.fetch(introspection, interface_name) do
      if Map.get(db_introspection_map, interface_name) == interface_major,
        do: {:ok, interface_major},
        else: {:error, :major_not_in_introspection}
    end
  end

  defp new_minor_different?(db_introspection_minor_map, interface_name, old_minor) do
    with {:ok, new_minor} <- Map.fetch(db_introspection_minor_map, interface_name) do
      if new_minor != old_minor,
        do: {:ok, new_minor},
        else: {:error, :minor_did_not_change}
    end
  end

  def ask_clean_session(state, timestamp) do
    Logger.warning("Disconnecting client and asking clean session.")
    %State{realm: realm, device_id: device_id} = state

    encoded_device_id = Device.encode_device_id(device_id)

    with :ok <- Queries.set_pending_empty_cache(realm, device_id, true),
         :ok <- force_disconnection(realm, encoded_device_id) do
      new_state = set_device_disconnected(state, timestamp)

      Logger.info("Successfully forced device disconnection.", tag: "forced_device_disconnection")

      :telemetry.execute(
        [:astarte, :data_updater_plant, :data_updater, :clean_session_request],
        %{},
        %{realm: new_state.realm}
      )

      {:ok, new_state}
    else
      {:error, reason} ->
        Logger.warning("Disconnect failed due to error: #{inspect(reason)}")
        # TODO: die gracefully here
        {:error, :clean_session_failed}
    end
  end

  @doc """
  Sets a device as disconnected, this does not foce device disconnection, but
  rather informs other astarte components that a device has been disconnected.
  """
  def set_device_disconnected(%State{} = state, timestamp) do
    timestamp_ms = div(timestamp, 10_000)

    Queries.set_device_disconnected!(
      state.realm,
      state.device_id,
      DateTime.from_unix!(timestamp_ms, :millisecond),
      state.total_received_msgs,
      state.total_received_bytes,
      state.interface_exchanged_msgs,
      state.interface_exchanged_bytes
    )

    maybe_execute_device_disconnected_trigger(state, timestamp_ms)

    %{state | connected: false}
    |> reset_encrypted_endpoints_key()
  end

  defp reset_encrypted_endpoints_key(state) do
    {:ok, key_state} = HandshakeState.transition(state.encrypted_endpoints_key, :reset)
    %{state | encrypted_endpoints_key: key_state}
  end

  defp maybe_execute_device_disconnected_trigger(%State{connected: false}, _), do: :ok

  defp maybe_execute_device_disconnected_trigger(state, timestamp_ms) do
    TriggersHandler.device_disconnected(
      state.realm,
      state.device_id,
      state.groups,
      timestamp_ms
    )

    :telemetry.execute(
      [:astarte, :data_updater_plant, :data_updater, :device_disconnection],
      %{},
      %{realm: state.realm}
    )
  end

  defp force_disconnection(realm, encoded_device_id) do
    case VMQPlugin.disconnect("#{realm}/#{encoded_device_id}", true) do
      # Successfully disconnected
      :ok ->
        :ok

      # Not found means it was already disconnected, succeed anyway
      {:error, :not_found} ->
        :ok

      # Some other error, return it
      {:error, reason} ->
        {:error, reason}
    end
  end

  def prune_device_properties(state, decoded_payload, timestamp) do
    with {:ok, paths_set} <-
           PayloadsDecoder.parse_device_properties_payload(decoded_payload, state.introspection) do
      Enum.each(state.introspection, fn {interface, _} ->
        # TODO: check result here
        Core.Interface.prune_interface(state, interface, paths_set, timestamp)
      end)

      :ok
    end
  end

  def resend_all_properties(state) do
    Logger.debug("Device introspection: #{inspect(state.introspection)}")

    Enum.reduce_while(state.introspection, {:ok, state}, fn {interface, major_version},
                                                            {:ok, state_acc} ->
      with {:ok, interface_descriptor, new_state} <-
             maybe_load_interface(state_acc, interface, major_version),
           :ok <- resend_all_interface_properties(new_state, interface_descriptor) do
        {:cont, {:ok, new_state}}
      else
        {:error, reason} = error ->
          Logger.warning(
            "Error while sending properties to device: #{inspect(reason)} on interface #{interface}"
          )

          {:halt, error}
      end
    end)
  end

  defp maybe_load_interface(state, interface, major_version) do
    maybe_descriptor = Map.get(state.interfaces, interface)

    case Core.Interface.maybe_handle_cache_miss(maybe_descriptor, interface, state) do
      {:ok, interface_descriptor, new_state} ->
        {:ok, interface_descriptor, new_state}

      {:error, :interface_loading_failed} ->
        {:error, {:interface_loading_failed, interface, major_version}}
    end
  end

  defp resend_all_interface_properties(
         %State{device_id: device_id, mappings: mappings} = state,
         %InterfaceDescriptor{type: :properties, ownership: :server} = interface_descriptor
       ) do
    encoded_device_id = Device.encode_device_id(device_id)

    mappings
    |> Enum.filter(fn {_endpoint_id, mapping} ->
      mapping.interface_id == interface_descriptor.interface_id
    end)
    |> Enum.reduce_while(:ok, fn {_endpoint_id, mapping}, :ok ->
      case resend_interface_mapping_properties(
             state,
             encoded_device_id,
             interface_descriptor,
             mapping
           ) do
        :ok ->
          {:cont, :ok}

        {:error, reason} ->
          Logger.warning(
            "Failed sending properties for interface #{interface_descriptor.name}: #{inspect(reason)}."
          )

          {:halt, {:error, :sending_properties_to_interface_failed}}
      end
    end)
  end

  defp resend_all_interface_properties(_state, %InterfaceDescriptor{} = _descriptor) do
    :ok
  end

  # Values of encrypted endpoints are stored encrypted at rest and travel
  # encrypted with the device's shared key, like any other server-owned publish.
  # Without a shared key they are not sent at all: never in clear.
  defp resend_interface_mapping_properties(
         state,
         encoded_device_id,
         interface_descriptor,
         %Mapping{encrypted: true} = mapping
       ) do
    case state.encrypted_endpoints_key do
      {:established, _data} ->
        state.realm
        |> Queries.retrieve_encrypted_property_values(
          state.device_id,
          interface_descriptor,
          mapping
        )
        |> Enum.reduce_while(:ok, fn row, :ok ->
          resend_encrypted_property(state, encoded_device_id, interface_descriptor, mapping, row)
        end)

      key_state ->
        Logger.warning(
          "Not resending the encrypted properties of #{interface_descriptor.name}#{mapping.endpoint}: device shared key not established. Current key agreement status: #{inspect(HandshakeState.name(key_state))}.",
          tag: "encrypted_properties_not_resent"
        )

        :ok
    end
  end

  defp resend_interface_mapping_properties(
         state,
         encoded_device_id,
         interface_descriptor,
         %Mapping{value_type: value_type} = mapping
       ) do
    column_name =
      CQLUtils.type_to_db_column_name(value_type) |> String.to_existing_atom()

    Queries.retrieve_property_values(state.realm, state.device_id, interface_descriptor, mapping)
    |> Enum.reduce_while(:ok, fn %{:path => path, ^column_name => value}, _acc ->
      payload = Cyanide.encode!(%{v: cast_bson_value(value_type, value)})

      handle_property_send(
        state.realm,
        encoded_device_id,
        interface_descriptor.name,
        path,
        payload
      )
    end)
  end

  defp resend_encrypted_property(state, encoded_device_id, interface_descriptor, mapping, row) do
    %{path: path, encryptedblob_value: stored_value, encrypted_dek: encrypted_dek} = row

    case decrypt_stored_value(state.realm, stored_value, encrypted_dek) do
      {:ok, value} ->
        # the whole BSON document is encrypted, as AppEngine does
        payload =
          %{v: cast_bson_value(mapping.value_type, value)}
          |> Cyanide.encode!()
          |> EncryptedMessages.encrypt(state.shared_secret)

        handle_property_send(
          state.realm,
          encoded_device_id,
          interface_descriptor.name,
          path,
          payload
        )

      :error ->
        Logger.warning(
          "Not resending the encrypted property #{interface_descriptor.name}#{path}: its stored value can't be decrypted.",
          tag: "encrypted_property_not_resent"
        )

        {:cont, :ok}
    end
  end

  defp decrypt_stored_value(realm, stored_value, encrypted_dek)
       when is_binary(stored_value) and is_binary(encrypted_dek) do
    case unwrap_and_decrypt(realm, stored_value, encrypted_dek) do
      {:ok, value} -> {:ok, value}
      _error -> :error
    end
  end

  defp decrypt_stored_value(_realm, _stored_value, _encrypted_dek), do: :error

  defp unwrap_and_decrypt(realm, stored_value, encrypted_dek) do
    with {:ok, dek} <- Secrets.decrypt_with_kek(realm, encrypted_dek),
         {:ok, plaintext} <- Secrets.decrypt_with_dek(stored_value, dek) do
      {:ok, :erlang.binary_to_term(plaintext)}
    end
  end

  defp handle_property_send(realm, encoded_device_id, interface_name, path, payload) do
    case send_value(realm, encoded_device_id, interface_name, path, payload) do
      {:ok, _bytes} ->
        # TODO: use the returned bytes count in stats
        {:cont, :ok}

      {:error, reason} ->
        {:halt, {:error, reason}}
    end
  end

  # The payload may be encrypted, so only the topic is logged
  defp send_value(realm, device_id_string, interface_name, path, payload) do
    topic = "#{realm}/#{device_id_string}/#{interface_name}#{path}"

    Logger.debug("Going to publish a property on #{topic}.")

    case VMQPlugin.publish(topic, payload, 2) do
      {:ok, %{local_matches: local, remote_matches: remote}} when local + remote == 1 ->
        {:ok, byte_size(topic) + byte_size(payload)}

      {:ok, %{local_matches: local, remote_matches: remote}} when local + remote > 1 ->
        # This should not happen so we print a warning, but we consider it a successful publish
        Logger.warning(
          "Multiple match while publishing a property on #{topic}.",
          tag: "publish_multiple_matches"
        )

        {:ok, byte_size(topic) + byte_size(payload)}

      {:ok, %{local_matches: local, remote_matches: remote}} when local + remote == 0 ->
        {:error, :session_not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp cast_bson_value(:binaryblob, value), do: %Cyanide.Binary{subtype: :generic, data: value}

  defp cast_bson_value(:binaryblobarray, value),
    do: Enum.map(value, &cast_bson_value(:binaryblob, &1))

  defp cast_bson_value(_value_type, value), do: value
end
