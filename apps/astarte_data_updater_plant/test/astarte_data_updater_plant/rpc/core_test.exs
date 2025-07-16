#
# This file is part of Astarte.
#
# Copyright 2025 SECO Mind Srl
#
#   pr  property "install_persistent_trigger/1 calls the `data_updater` server for specific device", context do
    %{realm_name: realm_name, device_fleet: device_fleet} = context

    check all trigger_name <- string(:alphanumeric, min_length: 2, max_length: 10),
              trigger_target <- binary() doy "install_persistent_trigger/1 calls the `data_updater` server for specific device", context do
    %{realm_name: realm_name, device_fleet: device_fleet} = context

    check all trigger_name <- string(:alphanumeric, min_length: 2, max_length: 10),
              trigger_target <- binary() dosed under the Apache License, Version 2.0 (the "License");
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

defmodule Astarte.DataUpdaterPlant.RPC.CoreTest do
  @moduledoc false
  alias Astarte.DataUpdaterPlant.DataUpdater
  alias Astarte.DataUpdaterPlant.RPC.Server.Core
  alias Astarte.DataUpdaterPlant.RPC.Core.Trigger
  alias Astarte.Core.Generators.Device, as: DeviceGenerator
  alias Astarte.Core.Triggers.SimpleTriggersProtobuf.DataTrigger
  alias Astarte.Core.Triggers.SimpleTriggersProtobuf.DeviceTrigger

  use Astarte.Cases.Data, async: true
  use Astarte.Cases.Device
  use ExUnitProperties

  use Mimic

  setup_all %{realm_name: realm_name, device: device} do
    
    fleet_count = 10
    
    additional_devices = 
      DeviceGenerator.device(interfaces: [])
      |> Stream.take(fleet_count - 1)
      |> Enum.to_list()
    
    all_devices = [device | additional_devices]
    
    device_fleet = 
      all_devices
      |> Enum.map(fn fleet_device ->
        {:ok, fleet_message_tracker} = DataUpdater.fetch_message_tracker(realm_name, fleet_device.encoded_id)

        {:ok, fleet_dup} =
          DataUpdater.fetch_data_updater_process(realm_name, fleet_device.encoded_id, fleet_message_tracker, true)

        Astarte.DataAccess.Config
        |> allow(self(), fleet_dup)

        GenServer.call(fleet_dup, :start)

        %{device: fleet_device, data_updater: fleet_dup}
      end)
    
    primary_device = List.first(device_fleet)
    
    %{
      device_fleet: device_fleet,
      device: primary_device.device,
      fleet_count: fleet_count,
      data_updater: primary_device.data_updater
    }
  end

  property "install_volatile_trigger/1 calls the `data_updater` server", context do
    %{realm_name: realm_name, device: device, data_updater: data_updater} = context

    check all volatile_trigger <- volatile_trigger(realm_name, device.encoded_id) do
      expected_request =
        {:handle_install_volatile_trigger, volatile_trigger.object_id,
         volatile_trigger.object_type, volatile_trigger.parent_id,
         volatile_trigger.simple_trigger_id, volatile_trigger.simple_trigger,
         volatile_trigger.trigger_target}

      expected_pid = self()

      DataUpdater.Server
      |> allow(self(), data_updater)
      |> expect(:handle_call, fn ^expected_request, {^expected_pid, _}, state ->
        {:reply, {:ok, true}, state}
      end)

      assert {:ok, _} = Core.install_volatile_trigger(volatile_trigger)
    end
  end

  property "delete_volatile_trigger/1 calls the `data_updater` server", context do
    %{realm_name: realm_name, device: device, data_updater: data_updater} = context

    check all trigger_id <- binary() do
      expected_request =
        {:handle_delete_volatile_trigger, trigger_id}

      expected_pid = self()

      DataUpdater.Server
      |> allow(self(), data_updater)
      |> expect(:handle_call, fn ^expected_request, {^expected_pid, _}, state ->
        {:reply, {:ok, true}, state}
      end)

      assert {:ok, _} =
               Core.delete_volatile_trigger(%{
                 realm_name: realm_name,
                 device_id: device.encoded_id,
                 trigger_id: trigger_id
               })
    end
  end

 
  property "install_persistent_trigger/1 handles multiple triggers correctly", context do
    %{realm_name: realm_name, device_fleet: device_fleet, :fleet_count} = context

      trigger_name = "test_trigger"

      triggers = make_persistent_trigger()

      trigger_target = make_trigger_target()

      devices_to_notify = 
        device_fleet
        |> Enum.map(fn %{device: device, data_updater: data_updater} ->
          {device.device_id, data_updater}
        end)

      Trigger
      |> allow(self(), :get_pids_for_realm)
      |> expect(:get_pids_for_realm, fn ^realm_name ->
        devices_to_notify
      end)

      device_fleet
      |> Enum.each(fn %{device: device, data_updater: data_updater} ->
        expected_request =
          {:handle_install_persistent_triggers, triggers, trigger_target}

        expected_pid = self()

        DataUpdater.Server
        |> allow(self(), data_updater)
        |> expect(:handle_call, fn ^expected_request, {^expected_pid, _}, state ->
          {:reply, {:ok, []}, state}
        end)
      end)

      request_data = %{
        trigger_name: trigger_name,
        realm: realm_name,
        triggers: triggers,
        trigger_target: trigger_target
      }

      mock_state = %{}

      assert {:reply, {:ok, results}, ^mock_state} = 
        Trigger.install_persistent_triggers(request_data, mock_state)
      
      assert is_list(results)

      assert length(results) == fleet_count 
      
      Enum.each(results, fn trigger_results ->
        assert is_list(trigger_results)
        assert length(trigger_results) == length(device_fleet)
        
        Enum.each(trigger_results, fn device_result ->
          assert device_result == {:ok, _} or device_result == {:exit, _}
        end)
      end)
    end
  end

  defp make_trigger_target() do
    %Astarte.Core.Triggers.SimpleTriggersProtobuf.AMQPTriggerTarget{
      version: 0, 
      simple_trigger_id: nil, 
      parent_trigger_id: uuid(), 
      routing_key: "trigger_engine", 
      static_headers: %{}, 
      exchange: nil, 
      message_expiration_ms: 0, 
      message_priority: 0, 
      message_persistent: false, 
      __unknown_fields__: []}
  end

  defp make_persistent_trigger() do
    simple_data_trigger =
        simple_trigger: {
          :data_trigger,
          %Astarte.Core.Triggers.SimpleTriggersProtobuf.DataTrigger{
            version: 0, 
            data_trigger_type: :INCOMING_DATA, 
            interface_name: "*", 
            interface_major: nil, 
            match_path: "/*", 
            value_match_operator: :ANY, 
            known_value: nil, 
            device_id: nil, 
            group_name: nil, 
            __unknown_fields__: []}
        }
      
    simple_device_trigger =
        simple_trigger: {
          :device_trigger, 
          %Astarte.Core.Triggers.SimpleTriggersProtobuf.DeviceTrigger{
            version: 0, 
            device_event_type: :DEVICE_CONNECTED, 
            device_id: nil, group_name: nil, 
            interface_name: nil, 
            interface_major: nil, 
            __unknown_fields__: []}
        }
    triggers = [%{simple_trigger: simple_data_trigger, object_id: :uuid()},
                  %{simple_trigger: simple_device_trigger, object_id: :uuid()}]
  
  end

  defp volatile_trigger(realm_name, device_id) do
    gen all object_id <- uuid(),
            object_type <- integer(),
            parent_id <- uuid(),
            trigger_id <- uuid(),
            simple_trigger <- binary(),
            trigger_target <- binary() do
      %{
        realm_name: realm_name,
        device_id: device_id,
        object_id: object_id,
        object_type: object_type,
        parent_id: parent_id,
        simple_trigger_id: trigger_id,
        simple_trigger: simple_trigger,
        trigger_target: trigger_target
      }
    end
  end

  defp uuid, do: repeatedly(&Ecto.UUID.bingenerate/0)
end
