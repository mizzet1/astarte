#
# This file is part of Astarte.
#
# Copyright 2026 Clea Srl
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

defmodule Astarte.AppEngine.API.Device.DeviceStatusTest do
  use ExUnit.Case, async: true

  alias Astarte.AppEngine.API.Device.DeviceStatus
  alias Astarte.AppEngine.API.Device.InterfaceInfo
  alias Astarte.Core.Device, as: CoreDevice
  alias Astarte.DataAccess.Device

  describe "from_db_row/1" do
    test "a device that never connected is not connected" do
      row = %Device{device_id: CoreDevice.random_device_id(), connected: nil}

      assert %DeviceStatus{connected: false} = DeviceStatus.from_db_row(row)
    end

    test "drops the interfaces with only a major or only a minor version" do
      row = %Device{
        device_id: CoreDevice.random_device_id(),
        introspection: %{"com.example.Sensor" => 1, "com.example.OnlyMajor" => 1},
        introspection_minor: %{"com.example.Sensor" => 2, "com.example.OnlyMinor" => 3}
      }

      assert %DeviceStatus{introspection: introspection} = DeviceStatus.from_db_row(row)
      assert %{"com.example.Sensor" => %InterfaceInfo{major: 1, minor: 2}} = introspection
      assert map_size(introspection) == 1
    end
  end
end
