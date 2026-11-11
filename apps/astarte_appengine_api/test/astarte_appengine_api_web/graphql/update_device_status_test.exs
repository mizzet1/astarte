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

defmodule Astarte.AppEngine.APIWeb.GraphQL.UpdateDeviceStatusTest do
  use Astarte.AppEngine.API.Cases.Data, async: true
  use Astarte.AppEngine.API.Cases.Conn
  use Astarte.Auth.Cases.AuthorizationModel

  alias Astarte.AppEngine.API.Device
  alias Astarte.AppEngine.API.Groups
  alias Astarte.AppEngine.API.Helpers.JWT
  alias Astarte.Core.Device, as: CoreDevice
  alias Astarte.DataAccess.Device, as: DatabaseDevice
  alias Astarte.DataAccess.Realms.Realm
  alias Astarte.DataAccess.Repo

  # the REST field names as aliases, so that the response can be compared with the REST one
  @mutation """
  mutation ($id: String!, $input: DeviceStatusInput!) {
    updateDeviceStatus(deviceId: $id, input: $input) {
      id
      connected
      introspection { ...interfaceInfo }
      previous_interfaces: previousInterfaces { ...interfaceInfo }
      aliases { key value }
      attributes { key value }
      groups
      total_received_msgs: totalReceivedMsgs
      total_received_bytes: totalReceivedBytes
      last_connection: lastConnection
      last_disconnection: lastDisconnection
      first_registration: firstRegistration
      first_credentials_request: firstCredentialsRequest
      last_seen_ip: lastSeenIp
      last_credentials_request_ip: lastCredentialsRequestIp
      credentials_inhibited: credentialsInhibited
      deletion_in_progress: deletionInProgress
    }
  }

  fragment interfaceInfo on InterfaceInfo {
    name
    major
    minor
    exchanged_msgs: exchangedMsgs
    exchanged_bytes: exchangedBytes
  }
  """

  @input %{attributes: [%{key: "line", value: "4"}]}

  @forbidden "Forbidden: OpenFGA denied access for this action"

  setup_all %{realm_name: realm_name, store_id: store_id} do
    JWT.install_public_key!(realm_name)

    write_tuples!(store_id, [
      %{
        user: "user:#{realm_name}/grantee",
        relation: "fleet_manager",
        object: "realm:#{realm_name}"
      }
    ])

    :ok
  end

  setup %{conn: conn, realm_name: realm_name} do
    device_id =
      insert_device!(realm_name, %DatabaseDevice{
        attributes: %{"plant" => "turin"},
        connected: true,
        introspection: %{"com.example.Sensor" => 1},
        introspection_minor: %{"com.example.Sensor" => 2},
        first_registration: ~U[2026-01-10 09:00:00.000Z],
        last_connection: ~U[2026-11-05 08:00:00.000Z],
        last_seen_ip: {198, 51, 100, 7},
        inhibit_credentials_request: false
      })

    # through the domain, so that the alias is also registered as a name of the realm
    {:ok, _status} =
      Device.merge_device_status(realm_name, device_id, %{
        "aliases" => %{"name" => unique_alias()}
      })

    {:ok, conn: put_req_header(conn, "astarte-realm", realm_name), device_id: device_id}
  end

  describe "authorization" do
    test "a realm role in the token grants the mutation", %{conn: conn, device_id: id} do
      token = JWT.gen_jwt_token_with_roles(["fleet_manager"])

      assert %{"data" => %{"updateDeviceStatus" => %{"id" => ^id}}} =
               update(conn, token, id, @input)
    end

    test "a realm role stored in OpenFGA grants the mutation", %{conn: conn, device_id: id} do
      token = JWT.gen_jwt_token_with_roles([], "grantee")

      assert %{"data" => %{"updateDeviceStatus" => %{"id" => ^id}}} =
               update(conn, token, id, @input)
    end

    test "a role on the device grants the mutation", context do
      %{conn: conn, realm_name: realm_name, device_id: id} = context
      grant!(context, "device_grantee", "fleet_manager", "device:#{realm_name}/#{id}")
      token = JWT.gen_jwt_token_with_roles([], "device_grantee")

      assert %{"data" => %{"updateDeviceStatus" => %{"id" => ^id}}} =
               update(conn, token, id, @input)
    end

    test "a read-only realm role doesn't grant the mutation", context do
      %{conn: conn, realm_name: realm_name, device_id: id} = context
      token = JWT.gen_jwt_token_with_roles(["observer"])
      status = rest_status(conn, realm_name, id)

      conn |> update(token, id, @input) |> assert_error(@forbidden)
      assert rest_status(conn, realm_name, id) == status
    end

    test "a read-only role on the device doesn't grant the mutation", context do
      %{conn: conn, realm_name: realm_name, device_id: id} = context
      grant!(context, "device_observer", "observer", "device:#{realm_name}/#{id}")
      token = JWT.gen_jwt_token_with_roles([], "device_observer")

      conn |> update(token, id, @input) |> assert_error(@forbidden)
    end

    test "a role on another device doesn't grant the mutation", context do
      %{conn: conn, realm_name: realm_name, device_id: id} = context
      other_id = insert_device!(realm_name, %DatabaseDevice{})
      grant!(context, "other_grantee", "fleet_manager", "device:#{realm_name}/#{other_id}")
      token = JWT.gen_jwt_token_with_roles([], "other_grantee")

      conn |> update(token, id, @input) |> assert_error(@forbidden)
    end

    test "a role on one of the device's groups doesn't grant the mutation", context do
      %{conn: conn, realm_name: realm_name, device_id: id} = context
      group_name = "line#{System.unique_integer([:positive])}"

      {:ok, _group} =
        Groups.create_group(realm_name, %{"group_name" => group_name, "devices" => [id]})

      grant!(
        context,
        "group_grantee",
        "fleet_manager",
        "device_group:#{realm_name}/#{group_name}"
      )

      token = JWT.gen_jwt_token_with_roles([], "group_grantee")

      conn |> update(token, id, @input) |> assert_error(@forbidden)
    end

    test "a device that doesn't exist is not found", %{conn: conn} do
      token = JWT.gen_jwt_token_with_roles(["fleet_manager"])
      id = CoreDevice.random_device_id() |> CoreDevice.encode_device_id()

      conn |> update(token, id, @input) |> assert_error("device_not_found")
    end

    test "a device that doesn't exist is forbidden without a role", %{conn: conn} do
      token = JWT.gen_jwt_token_with_roles([])
      id = CoreDevice.random_device_id() |> CoreDevice.encode_device_id()

      conn |> update(token, id, @input) |> assert_error(@forbidden)
    end

    test "an invalid device id is rejected", %{conn: conn} do
      token = JWT.gen_jwt_token_with_roles(["fleet_manager"])

      conn |> update(token, "notadeviceid", @input) |> assert_error("Invalid argument: device_id")
    end
  end

  describe "aliases" do
    test "are set and replaced", %{conn: conn, realm_name: realm_name, device_id: id} do
      [name, serial] = [unique_alias(), unique_alias()]
      input = %{aliases: [%{key: "name", value: name}, %{key: "serial", value: serial}]}

      assert %{"aliases" => aliases} = update!(conn, id, input)
      assert aliases == %{"name" => name, "serial" => serial}
      assert rest_status(conn, realm_name, id)["aliases"] == aliases
    end

    test "are removed by a null value", %{conn: conn, realm_name: realm_name, device_id: id} do
      input = %{aliases: [%{key: "name", value: nil}]}

      assert %{"aliases" => aliases} = update!(conn, id, input)
      assert aliases == %{}
      assert rest_status(conn, realm_name, id)["aliases"] == %{}
    end

    test "can't be taken from another device", %{
      conn: conn,
      realm_name: realm_name,
      device_id: id
    } do
      other_id = insert_device!(realm_name, %DatabaseDevice{})
      taken = unique_alias()

      {:ok, _status} =
        Device.merge_device_status(realm_name, other_id, %{"aliases" => %{"name" => taken}})

      input = %{aliases: [%{key: "name", value: taken}]}

      conn |> update(id, input) |> assert_error("alias_already_in_use")
    end

    test "can't be removed when the device doesn't have the tag", %{conn: conn, device_id: id} do
      input = %{aliases: [%{key: "serial", value: nil}]}

      conn |> update(id, input) |> assert_error("alias_tag_not_found")
    end

    test "can't have an empty tag or value", %{conn: conn, device_id: id} do
      for entry <- [%{key: "", value: unique_alias()}, %{key: "name", value: ""}] do
        conn |> update(id, %{aliases: [entry]}) |> assert_error("invalid_alias")
      end
    end

    test "can't list a tag twice or omit its value", %{conn: conn, device_id: id} do
      twice = [%{key: "name", value: unique_alias()}, %{key: "name", value: nil}]

      for entries <- [twice, [%{key: "name"}]] do
        conn |> update(id, %{aliases: entries}) |> assert_error("invalid_alias")
      end
    end
  end

  describe "attributes" do
    test "are set and replaced, also to an empty value", context do
      %{conn: conn, realm_name: realm_name, device_id: id} = context
      input = %{attributes: [%{key: "plant", value: "milan"}, %{key: "line", value: ""}]}

      assert %{"attributes" => attributes} = update!(conn, id, input)
      assert attributes == %{"plant" => "milan", "line" => ""}
      assert rest_status(conn, realm_name, id)["attributes"] == attributes
    end

    test "are removed by a null value", %{conn: conn, realm_name: realm_name, device_id: id} do
      input = %{attributes: [%{key: "plant", value: nil}]}

      assert %{"attributes" => attributes} = update!(conn, id, input)
      assert attributes == %{}
      assert rest_status(conn, realm_name, id)["attributes"] == %{}
    end

    test "can't be removed when the device doesn't have the key", %{conn: conn, device_id: id} do
      input = %{attributes: [%{key: "line", value: nil}]}

      conn |> update(id, input) |> assert_error("attribute_key_not_found")
    end

    test "can't have an empty key", %{conn: conn, device_id: id} do
      input = %{attributes: [%{key: "", value: "milan"}]}

      conn |> update(id, input) |> assert_error("invalid_attributes")
    end

    test "can't list a key twice or omit its value", %{conn: conn, device_id: id} do
      twice = [%{key: "plant", value: "milan"}, %{key: "plant", value: nil}]

      for entries <- [twice, [%{key: "plant"}]] do
        conn |> update(id, %{attributes: entries}) |> assert_error("invalid_attributes")
      end
    end
  end

  describe "credentialsInhibited" do
    test "is set to true and to false", %{conn: conn, realm_name: realm_name, device_id: id} do
      for value <- [true, false] do
        assert %{"credentials_inhibited" => ^value} =
                 update!(conn, id, %{credentials_inhibited: value})

        assert %{"credentials_inhibited" => ^value} = rest_status(conn, realm_name, id)
      end
    end

    test "is cleared by a null", %{conn: conn, realm_name: realm_name, device_id: id} do
      update!(conn, id, %{credentials_inhibited: true})

      assert %{"credentials_inhibited" => nil} = update!(conn, id, %{credentials_inhibited: nil})
      assert %{"credentials_inhibited" => nil} = rest_status(conn, realm_name, id)
    end

    test "is left unchanged when omitted", %{conn: conn, device_id: id} do
      update!(conn, id, %{credentials_inhibited: true})

      assert %{"credentials_inhibited" => true} = update!(conn, id, @input)
    end

    test "must be a boolean", %{conn: conn, realm_name: realm_name, device_id: id} do
      status = rest_status(conn, realm_name, id)

      response = update(conn, id, %{credentials_inhibited: "yes"})

      assert %{"errors" => [%{"message" => message}]} = response
      assert message =~ ~s(Expected type "Boolean", found "yes")
      refute Map.has_key?(response, "data")
      assert rest_status(conn, realm_name, id) == status
    end
  end

  test "an empty input or null lists change nothing", context do
    %{conn: conn, realm_name: realm_name, device_id: id} = context
    status = rest_status(conn, realm_name, id)

    for input <- [%{}, %{aliases: nil, attributes: nil}] do
      assert update!(conn, id, input) == status
    end
  end

  test "an update with an invalid change changes nothing", context do
    %{conn: conn, realm_name: realm_name, device_id: id} = context
    status = rest_status(conn, realm_name, id)

    input = %{
      aliases: [%{key: "name", value: unique_alias()}],
      attributes: [%{key: "", value: "milan"}],
      credentials_inhibited: true
    }

    conn |> update(id, input) |> assert_error("invalid_attributes")
    assert rest_status(conn, realm_name, id) == status
  end

  test "a device that never connected is not connected", %{conn: conn, realm_name: realm_name} do
    id = insert_device!(realm_name, %DatabaseDevice{})

    assert %{"connected" => false} = update!(conn, id, @input)
  end

  test "returns the device status of the REST API", context do
    %{conn: conn, realm_name: realm_name, device_id: id} = context

    input = %{
      aliases: [%{key: "serial", value: unique_alias()}],
      attributes: [%{key: "plant", value: "milan"}],
      credentials_inhibited: true
    }

    device = update!(conn, id, input)

    # the same changes again, through REST: they are already applied, so the device doesn't change
    patch = %{
      "aliases" => Map.new(input.aliases, &{&1.key, &1.value}),
      "attributes" => Map.new(input.attributes, &{&1.key, &1.value}),
      "credentials_inhibited" => true
    }

    rest_device =
      conn
      |> put_req_header("authorization", "bearer #{JWT.gen_jwt_all_access_token()}")
      |> put_req_header("content-type", "application/merge-patch+json")
      |> patch("/v1/#{realm_name}/devices/#{id}", Jason.encode!(%{data: patch}))
      |> json_response(200)
      |> Map.fetch!("data")

    assert device == rest_device
  end

  defp insert_device!(realm_name, device) do
    device_id = CoreDevice.random_device_id()
    Repo.insert!(%{device | device_id: device_id}, prefix: Realm.keyspace_name(realm_name))
    CoreDevice.encode_device_id(device_id)
  end

  defp grant!(%{realm_name: realm_name, store_id: store_id}, user, relation, object) do
    tuple = %{user: "user:#{realm_name}/#{user}", relation: relation, object: object}
    write_tuples!(store_id, [tuple])
  end

  defp unique_alias, do: "press#{System.unique_integer([:positive])}"

  defp update(conn, id, input),
    do: update(conn, JWT.gen_jwt_token_with_roles(["fleet_manager"]), id, input)

  defp update(conn, token, id, input) do
    conn
    |> put_req_header("authorization", "bearer #{token}")
    |> put_req_header("content-type", "application/json")
    |> post("/v1/graphql", Jason.encode!(%{query: @mutation, variables: %{id: id, input: input}}))
    |> json_response(200)
  end

  # the updated device, in the shape of the REST API
  defp update!(conn, id, input) do
    assert %{"data" => %{"updateDeviceStatus" => %{} = device}} = update(conn, id, input)
    rest_shape(device)
  end

  defp rest_status(conn, realm_name, id) do
    conn
    |> put_req_header("authorization", "bearer #{JWT.gen_jwt_all_access_token()}")
    |> get("/v1/#{realm_name}/devices/#{id}")
    |> json_response(200)
    |> Map.fetch!("data")
  end

  defp assert_error(response, message) do
    assert %{"data" => %{"updateDeviceStatus" => nil}, "errors" => [%{"message" => ^message}]} =
             response
  end

  # REST returns aliases, attributes and introspection as objects keyed by name
  defp rest_shape(device) do
    device
    |> Map.update!("aliases", &entries_to_map/1)
    |> Map.update!("attributes", &entries_to_map/1)
    |> Map.update!("introspection", &Map.new(&1, fn info -> Map.pop!(info, "name") end))
  end

  defp entries_to_map(entries), do: Map.new(entries, &{&1["key"], &1["value"]})
end
