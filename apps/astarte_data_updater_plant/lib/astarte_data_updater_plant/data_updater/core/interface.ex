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

defmodule Astarte.DataUpdaterPlant.DataUpdater.Core.Interface do
  @moduledoc """
  Core part of the data_updater message processing.

  This module contains functions and utilities to process interfaces.
  """
  alias Astarte.Core.CQLUtils
  alias Astarte.Core.Device, as: CoreDevice
  alias Astarte.Core.InterfaceDescriptor
  alias Astarte.Core.Mapping
  alias Astarte.Core.Mapping.EndpointsAutomaton
  alias Astarte.DataAccess.Device
  alias Astarte.DataAccess.Interface
  alias Astarte.DataAccess.Mappings
  alias Astarte.DataUpdaterPlant.DataUpdater.Queries
  alias Astarte.DataUpdaterPlant.DataUpdater.State
  alias Astarte.DataUpdaterPlant.TriggersHandler

  require Logger

  @interface_lifespan_decimicroseconds 60 * 10 * 1000 * 10_000

  def maybe_handle_cache_miss(nil, interface_name, state) do
    with {:ok, major_version} <-
           Device.interface_version(state.realm, state.device_id, interface_name),
         {:ok, interface_row} <-
           Interface.retrieve_interface_row(state.realm, interface_name, major_version),
         %InterfaceDescriptor{interface_id: interface_id} = interface_descriptor <-
           InterfaceDescriptor.from_db_result!(interface_row),
         {:ok, mappings} <-
           Mappings.fetch_interface_mappings_map(state.realm, interface_id) do
      new_interfaces_by_expiry =
        state.interfaces_by_expiry ++
          [{state.last_seen_message + @interface_lifespan_decimicroseconds, interface_name}]

      new_state = %State{
        state
        | interfaces: Map.put(state.interfaces, interface_name, interface_descriptor),
          interface_ids_to_name:
            Map.put(
              state.interface_ids_to_name,
              interface_id,
              interface_name
            ),
          interfaces_by_expiry: new_interfaces_by_expiry,
          mappings: Map.merge(state.mappings, mappings)
      }

      # TODO: make everything with-friendly
      {:ok, interface_descriptor, new_state}
    else
      error ->
        log_unless_known_cache_miss_error(error)
        {:error, :interface_loading_failed}
    end
  end

  def maybe_handle_cache_miss(interface_descriptor, _interface_name, state) do
    {:ok, interface_descriptor, state}
  end

  # Known errors. TODO: handle specific cases (e.g. ask for new introspection etc.)
  @known_cache_miss_errors [
    :interface_not_in_introspection,
    :device_not_found,
    :database_error,
    :interface_not_found
  ]

  defp log_unless_known_cache_miss_error({:error, reason})
       when reason in @known_cache_miss_errors do
    :ok
  end

  defp log_unless_known_cache_miss_error(other) do
    Logger.warning("maybe_handle_cache_miss failed: #{inspect(other)}")
  end

  def prune_interface(state, interface, all_paths_set, timestamp) do
    with {:ok, interface_descriptor, new_state} <-
           maybe_handle_cache_miss(
             Map.get(state.interfaces, interface),
             interface,
             state
           ) do
      cond do
        interface_descriptor.type != :properties ->
          # TODO: nobody uses new_state
          {:ok, new_state}

        interface_descriptor.ownership != :device ->
          Logger.warning("Tried to prune server owned interface: #{interface}.")
          {:error, :maybe_outdated_introspection}

        true ->
          do_prune(new_state, interface_descriptor, all_paths_set, timestamp)
          # TODO: nobody uses new_state
          {:ok, new_state}
      end
    end
  end

  defp do_prune(state, interface_descriptor, all_paths_set, timestamp) do
    hw_id = CoreDevice.encode_device_id(state.device_id)

    context = %{
      state: state,
      hardware_id: hw_id,
      interface_id: interface_descriptor.interface_id,
      interface: interface_descriptor.name,
      value_timestamp: timestamp,
      endpoint_id: nil,
      path: nil
    }

    each_interface_mapping(state.mappings, interface_descriptor, fn mapping ->
      prune_mapping_paths(
        state,
        interface_descriptor,
        mapping.endpoint_id,
        all_paths_set,
        context
      )
    end)
  end

  defp prune_mapping_paths(
         state,
         interface_descriptor,
         endpoint_id,
         all_paths_set,
         context
       ) do
    database_paths =
      Queries.all_device_owned_property_endpoint_paths!(
        state.realm,
        state.device_id,
        interface_descriptor,
        endpoint_id
      )

    interface_name = interface_descriptor.name
    paths = database_paths |> Enum.map(&{interface_name, &1}) |> MapSet.new()
    unset_paths = MapSet.difference(paths, all_paths_set)

    unset_paths
    |> Enum.each(fn {_interface_name, path} ->
      prune_path(
        state,
        interface_descriptor,
        endpoint_id,
        path,
        context
      )
    end)
  end

  defp prune_path(
         state,
         interface_descriptor,
         endpoint_id,
         path,
         context
       ) do
    Queries.delete_property_from_db(
      state.realm,
      state.device_id,
      interface_descriptor,
      endpoint_id,
      path
    )

    context = %{
      context
      | endpoint_id: endpoint_id,
        path: path
    }

    TriggersHandler.path_removed(context)
  end

  def each_interface_mapping(mappings, interface_descriptor, fun) do
    Enum.each(mappings, fn {_endpoint_id, mapping} ->
      if mapping.interface_id == interface_descriptor.interface_id do
        fun.(mapping)
      end
    end)
  end

  def resolve_path(path, interface_descriptor, mappings) do
    case interface_descriptor.aggregation do
      :individual ->
        resolve_individual_path(path, interface_descriptor, mappings)

      :object ->
        resolve_object_path(path, interface_descriptor, mappings)
    end
  end

  defp resolve_individual_path(path, interface_descriptor, mappings) do
    with {:ok, endpoint_id} <-
           EndpointsAutomaton.resolve_path(path, interface_descriptor.automaton),
         {:ok, endpoint} <- Map.fetch(mappings, endpoint_id) do
      {:ok, endpoint}
    else
      result ->
        handle_individual_resolve_result(result, path, mappings)
    end
  end

  defp handle_individual_resolve_result({:guessed, guessed_endpoints}, _path, _mappings) do
    {:guessed, guessed_endpoints}
  end

  defp handle_individual_resolve_result(:error, path, mappings) do
    # Map.fetch failed
    Logger.warning(
      "endpoint_id for path #{inspect(path)} not found in mappings #{inspect(mappings)}."
    )

    {:error, :mapping_not_found}
  end

  defp handle_individual_resolve_result({:error, reason}, _path, _mappings) do
    Logger.warning("EndpointsAutomaton.resolve_path failed with reason #{inspect(reason)}.")
    {:error, :mapping_not_found}
  end

  defp resolve_object_path(path, interface_descriptor, mappings) do
    with {:guessed, [first_endpoint_id | _tail] = guessed_endpoints} <-
           EndpointsAutomaton.resolve_path(path, interface_descriptor.automaton),
         :ok <- check_object_aggregation_prefix(path, guessed_endpoints, mappings),
         {:ok, first_mapping} <- Map.fetch(mappings, first_endpoint_id) do
      # We return the first guessed mapping changing just its endpoint id, using the canonical
      # endpoint id used in object aggregated interfaces. This way all mapping properties
      # (database_retention_ttl, reliability etc) are correctly set since they're the same in
      # all mappings (this is enforced by Realm Management when the interface is installed)

      endpoint_id =
        CQLUtils.endpoint_id(
          interface_descriptor.name,
          interface_descriptor.major_version,
          ""
        )

      {:ok, %{first_mapping | endpoint_id: endpoint_id}}
    else
      result ->
        log_object_resolve_error(result, path, interface_descriptor, mappings)
        {:error, :mapping_not_found}
    end
  end

  defp log_object_resolve_error(:error, path, _interface_descriptor, mappings) do
    # Map.fetch failed
    Logger.warning(
      "endpoint_id for path #{inspect(path)} not found in mappings #{inspect(mappings)}."
    )
  end

  defp log_object_resolve_error({:ok, _endpoint_id}, path, interface_descriptor, _mappings) do
    # This is invalid here, publish doesn't happen on endpoints
    # in object aggregated interfaces
    Logger.warning(
      "Tried to publish on endpoint #{inspect(path)} for object aggregated " <>
        "interface #{inspect(interface_descriptor.name)}. You should publish on " <>
        "the common prefix",
      tag: "invalid_path"
    )
  end

  defp log_object_resolve_error(_error, path, interface_descriptor, _mappings) do
    Logger.warning(
      "Tried to publish on invalid path #{inspect(path)} for object aggregated " <>
        "interface #{inspect(interface_descriptor.name)}",
      tag: "invalid_path"
    )
  end

  defp check_object_aggregation_prefix(path, guessed_endpoints, mappings) do
    received_path_depth = path_or_endpoint_depth(path)

    Enum.reduce_while(guessed_endpoints, :ok, fn
      endpoint_id, _acc ->
        with {:ok, %Mapping{endpoint: endpoint}} <- Map.fetch(mappings, endpoint_id),
             endpoint_depth when received_path_depth == endpoint_depth - 1 <-
               path_or_endpoint_depth(endpoint) do
          {:cont, :ok}
        else
          _ ->
            {:halt, {:error, :invalid_object_aggregation_path}}
        end
    end)
  end

  defp path_or_endpoint_depth(path) when is_binary(path) do
    String.split(path, "/", trim: true)
    |> length()
  end

  def extract_mappings(%InterfaceDescriptor{aggregation: :individual}, mapping, _mappings) do
    mapping
  end

  def extract_mappings(
        %InterfaceDescriptor{aggregation: :object},
        _mapping,
        mappings
      ) do
    mappings
    |> Map.new(fn {_id, m} ->
      key = m.endpoint |> String.split("/") |> List.last()
      {key, m}
    end)
  end

  def forget_interfaces(state, []) do
    state
  end

  def forget_interfaces(state, interfaces_to_drop) do
    iface_ids_to_drop =
      Enum.filter(interfaces_to_drop, &Map.has_key?(state.interfaces, &1))
      |> Enum.map(fn iface ->
        Map.fetch!(state.interfaces, iface).interface_id
      end)

    updated_triggers =
      Enum.reduce(iface_ids_to_drop, state.data_triggers, fn interface_id, data_triggers ->
        Enum.reject(data_triggers, fn {{_event_type, iface_id, _endpoint}, _val} ->
          iface_id == interface_id
        end)
        |> Enum.into(%{})
      end)

    updated_mappings =
      Enum.reduce(iface_ids_to_drop, state.mappings, fn interface_id, mappings ->
        Enum.reject(mappings, fn {_endpoint_id, mapping} ->
          mapping.interface_id == interface_id
        end)
        |> Enum.into(%{})
      end)

    updated_ids =
      Enum.reduce(iface_ids_to_drop, state.interface_ids_to_name, fn interface_id, ids ->
        Map.delete(ids, interface_id)
      end)

    updated_interfaces =
      Enum.reduce(interfaces_to_drop, state.interfaces, fn iface, ifaces ->
        Map.delete(ifaces, iface)
      end)

    %{
      state
      | interfaces: updated_interfaces,
        interface_ids_to_name: updated_ids,
        mappings: updated_mappings,
        data_triggers: updated_triggers
    }
  end

  def gather_interface_property_paths(
        %State{device_id: device_id, mappings: mappings, realm: realm} = _state,
        %InterfaceDescriptor{type: :properties, ownership: :server} = interface_descriptor
      ) do
    reduce_interface_mapping(mappings, interface_descriptor, [], fn mapping, i_acc ->
      Queries.retrieve_property_values(realm, device_id, interface_descriptor, mapping)
      |> Enum.reduce(i_acc, fn %{path: path}, acc ->
        ["#{interface_descriptor.name}#{path}" | acc]
      end)
    end)
  end

  def gather_interface_property_paths(_state, %InterfaceDescriptor{} = _descriptor) do
    []
  end

  defp reduce_interface_mapping(mappings, interface_descriptor, initial_acc, fun) do
    Enum.reduce(mappings, initial_acc, fn {_endpoint_id, mapping}, acc ->
      if mapping.interface_id == interface_descriptor.interface_id do
        fun.(mapping, acc)
      else
        acc
      end
    end)
  end
end
