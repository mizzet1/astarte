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

defmodule Astarte.DataUpdaterPlant.RPC.Core.StateHandler do
  alias Astarte.DataUpdaterPlant.RPC.State
  alias Astarte.DataUpdaterPlant.RPC.Device
  require Logger

  def add_device(
        %State{devices: devices} = state,
        %Device{device_id: device_id, realm: realm} = device
      ) do
    Logger.debug("add_device called with state: #{inspect(state)}, device: #{inspect(device)}")

    updated_devices = Map.put(devices, {device_id, realm}, device)
    Logger.debug("Updated devices map: #{inspect(updated_devices)}")

    %State{state | devices: updated_devices}
  end

  def remove_device(%State{devices: devices} = state, device_id, realm) do
    updated_devices = Map.delete(devices, {device_id, realm})
    %State{state | devices: updated_devices}
  end

  def update_device_groups(%State{devices: devices} = state, device_id, realm, new_groups) do
    case Map.get(devices, {device_id, realm}) do
      nil ->
        {:error, :device_not_found}

      %Device{} = device ->
        updated_device = %Device{device | groups: new_groups}
        updated_devices = Map.put(devices, {device_id, realm}, updated_device)
        %State{state | devices: updated_devices}
    end
  end
end
