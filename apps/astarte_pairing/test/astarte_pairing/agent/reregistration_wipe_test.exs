#
# This file is part of Astarte.
#
# Copyright 2026 SECO Mind Srl
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

defmodule Astarte.Pairing.Agent.ReregistrationWipeTest do
  @moduledoc """
  Reproduces (or refutes) the hypothesis: unregistering a device and then
  re-registering it WITHOUT `initial_introspection` wipes its introspection
  for real in the DB - a genuine write, not the silent no-op found in
  astarte_data_updater_plant's update_device_introspection!/4.
  """

  use Astarte.Cases.Data, async: true

  alias Astarte.Core.Device
  alias Astarte.DataAccess.Devices.Device, as: DatabaseDevice
  alias Astarte.DataAccess.Realms.Realm
  alias Astarte.DataAccess.Repo
  alias Astarte.Pairing.Agent

  test "unregister + re-register WITHOUT initial_introspection wipes a previously-populated introspection",
       %{realm_name: realm_name} do
    hw_id = Device.random_device_id() |> Device.encode_device_id()
    keyspace = Realm.keyspace_name(realm_name)

    # Step 1: register with a real introspection.
    initial_introspection = %{
      "org.astarteplatform.Values" => %{"major" => 0, "minor" => 4},
      "org.astarteplatform.OtherValues" => %{"major" => 1, "minor" => 0}
    }

    assert {:ok, _response} =
             Agent.register_device(realm_name, %{
               "hw_id" => hw_id,
               "initial_introspection" => initial_introspection
             })

    row_after_register = Repo.get!(DatabaseDevice, decode(hw_id), prefix: keyspace)
    assert map_size(row_after_register.introspection) == 2
    assert row_after_register.first_credentials_request == nil

    # Step 2: unregister. Per the API contract ("All data belonging to the
    # device will be kept as is") this should ONLY clear credentials fields.
    assert :ok = Agent.unregister_device(realm_name, hw_id)

    row_after_unregister = Repo.get!(DatabaseDevice, decode(hw_id), prefix: keyspace)

    assert row_after_unregister.introspection == row_after_register.introspection,
           "unregister must not touch introspection at all"

    # Step 3: re-register WITHOUT initial_introspection - this is the
    # hypothesized wipe.
    assert {:ok, _response} =
             Agent.register_device(realm_name, %{"hw_id" => hw_id})

    row_after_reregister = Repo.get!(DatabaseDevice, decode(hw_id), prefix: keyspace)

    IO.puts(
      "\n[re-registration evidence] introspection before: #{inspect(row_after_unregister.introspection)}, after re-register without initial_introspection: #{inspect(row_after_reregister.introspection)}\n"
    )

    assert row_after_reregister.introspection == %{},
           "re-registering without initial_introspection genuinely wipes introspection, unlike the DUP silent no-op"

    assert row_after_reregister.first_credentials_request == nil,
           "consistent with what we observed in production: after this sequence the device looks like it never made its first credentials request"
  end

  defp decode(encoded_device_id) do
    {:ok, device_id} = Device.decode_device_id(encoded_device_id)
    device_id
  end
end
