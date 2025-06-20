#
# This file is part of Astarte.
#
# Copyright 2017 - 2025 SECO Mind Srl
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

defmodule Astarte.DataUpdaterPlant.RPC.Core.Trigger do
  alias ElixirSense.Log
  alias Astarte.DataUpdaterPlant.RPC.State
  alias Astarte.DataUpdaterPlant.RPC.Device
  alias Astarte.DataUpdaterPlant.DataUpdater
  require Logger

  def get_trigger_installation_scope(simple_trigger) do
    case simple_trigger do
      {:data_trigger, %Astarte.Core.Triggers.SimpleTriggersProtobuf.DataTrigger{} = data_trigger} ->
        cond do
          Map.has_key?(data_trigger, :group_name) and not is_nil(data_trigger.group_name) ->
            {:data_trigger_group, data_trigger.group_name}

          Map.has_key?(data_trigger, :device_id) and not is_nil(data_trigger.device_id) ->
            {:data_trigger_device, data_trigger.device_id}

          true ->
            {:all, nil}
        end

      {:device_trigger,
       %Astarte.Core.Triggers.SimpleTriggersProtobuf.DeviceTrigger{device_id: device_id}} ->
        {:device, device_id}
    end
  end

  def get_devices_to_notify(%State{} = state, scope) do
    case scope do
      {:all, nil} ->
        state
        |> fetch_all_devices()
        |> Enum.map(fn %Device{device_id: device_id, realm: realm} -> {device_id, realm} end)

      {:data_trigger_group, group_name} ->
        state
        |> fetch_devices_by_group(group_name)
        |> Enum.map(fn %Device{device_id: device_id, realm: realm} -> {device_id, realm} end)

      {:device, device_id} ->
        case fetch_device_by_id(state, device_id) do
          {:ok, {device_id, realm}} ->
            [{device_id, realm}]

          {:error, :device_not_found} ->
            Logger.error("Device with ID #{device_id} not found.")
            []
        end

      {:data_trigger_device, device_id} ->
        case fetch_device_by_id(state, device_id) do
          {:ok, {device_id, realm}} ->
            [{device_id, realm}]

          {:error, :device_not_found} ->
            Logger.error("Device with ID #{device_id} not found.")
            []
        end

      _ ->
        Logger.error("Unknown scope for trigger installation detected: #{inspect(scope)}")
        []
    end
  end

  def install_persistent_triggers(triggers, state) do
    Logger.info("Received request to install persistent triggers ...")
    Logger.info("Triggers details: #{inspect(triggers)}")
    %{triggers: triggers, trigger_target: trigger_target} = triggers

    results =
      triggers
      |> Enum.map(fn %{simple_trigger: simple_trigger} ->
        scope = get_trigger_installation_scope(simple_trigger)
        Logger.info("Determined scope for trigger installation: #{inspect(scope)}")

        devices_to_notify = get_devices_to_notify(state, scope)

        Logger.info("Devices to notify for trigger installation: #{inspect(devices_to_notify)}")

        devices_to_notify
        |> Task.async_stream(
          fn {device_id, realm} ->
            Logger.info("Processing device #{device_id} in realm #{realm}.")

            with :ok <- DataUpdater.verify_device_exists(realm, device_id),
                 {:ok, message_tracker} <- DataUpdater.fetch_message_tracker(realm, device_id),
                 {:ok, dup} <-
                   DataUpdater.fetch_data_updater_process(realm, device_id, message_tracker) do
              Logger.info("Successfully fetched DataUpdaterProcess for device #{device_id}.")

              reply =
                GenServer.call(
                  dup,
                  {:handle_install_persistent_triggers, triggers, trigger_target}
                )

              Logger.info("Trigger installed successfully for device #{device_id}.")
              {:ok, reply}
            else
              {:error, error} ->
                Logger.error(
                  "Error #{inspect(error)} while processing device #{device_id} for `install_persistent_triggers`."
                )

                {:error, error}
            end
          end,
          max_concurrency: 10,
          timeout: :infinity
        )
        |> Enum.to_list()
      end)

    {:reply, {:ok, results}, state}
  end

  def convert_extended_device_id_to_string(extended_device_id) do
    Ecto.UUID.dump!(extended_device_id)
    |> Astarte.Core.Device.encode_device_id()
  end

  def fetch_devices_by_group(%State{devices: devices}, group) do
    devices
    |> Map.values()
    |> Enum.filter(fn %Device{groups: groups} -> groups && group in groups end)
  end

  # TODO: check if the cache is stale
  def fetch_device_by_id(%State{devices: devices}, device_id) do
    with :error <- Map.fetch(devices, device_id) do
      {:error, :device_not_found}
    end
  end

  defp fetch_all_devices(%State{devices: devices}), do: Map.values(devices)
end
