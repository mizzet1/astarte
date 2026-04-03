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

defmodule Astarte.PairingWeb.Controllers.OwnershipVoucherControllerTest do
  use Astarte.Cases.Conn, async: true
  use Astarte.Cases.Data
  use Mimic

  alias Astarte.Pairing.Config
  alias Astarte.Secrets
  alias Astarte.Secrets.Key

  import Astarte.Helpers.FDO

  @sample_key_name "owner_key"

  @sample_private_key_pem """
  -----BEGIN EC PRIVATE KEY-----
  MHcCAQEEIH41aNoVYh0/QX8FzUVu5aojDvaCPilLSeWNEL78fAaBoAoGCCqGSM49
  AwEHoUQDQgAEroZPR93c3oUpkr8ylwnnGEaX/YzUmViGx/YpptKXBFFzz81Vg+Xf
  4upGU3lmnv6lf1yQulog6rwkuptncIx4eg==
  -----END EC PRIVATE KEY-----
  """

  @sample_ownership_voucher_pem """
  -----BEGIN OWNERSHIP VOUCHER-----
  hRhlWQGChhhlUOYZotoizUjOquGbU1cCpE6BhIIDQxkfkoICRUR/AAABggRDGR+S
  ggxBAWtwMjU2LWRldmljZYMKAVkBHjCCARowgcGgAwIBAgIDAeJAMAoGCCqGSM49
  BAMCMBYxFDASBgNVBAMMC1Rlc3QgRGV2aWNlMB4XDTI0MDEwMTAwMDAwMFoXDTM0
  MDEwMTAwMDAwMFowFjEUMBIGA1UEAwwLVGVzdCBEZXZpY2UwWTATBgcqhkjOPQIB
  BggqhkjOPQMBBwNCAASKjFCvAt3G6w2GppyTEpNFzwchyV2pNYL2Ca0H8ShDuUEM
  3ONRnPelcwITVQ4A5C/H+5qWzvyLFRuiNbQB0MTCMAoGCCqGSM49BAMCA0gAMEUC
  IQDSYOKHW2XEYsGgin9F0rcvagwFR0iGslc/JASAbJ+t1wIgapYqe5zuEAR/JQ+P
  2QnoOVUeMXwDwpj9Fj6GaZcnIEyCL1ggIGpDcE6kqfCqpDWG8SWZtI+wuVhhY+nj
  tlo2Ny4TDnmCBVgg/CH+PV54HKflKJfZn6YfgfFgV1TA860DfTRxNZ9ouxSBWQEe
  MIIBGjCBwaADAgECAgMB4kAwCgYIKoZIzj0EAwIwFjEUMBIGA1UEAwwLVGVzdCBE
  ZXZpY2UwHhcNMjQwMTAxMDAwMDAwWhcNMzQwMTAxMDAwMDAwWjAWMRQwEgYDVQQD
  DAtUZXN0IERldmljZTBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABIqMUK8C3cbr
  DYamnJMSk0XPByHJXak1gvYJrQfxKEO5QQzc41Gc96VzAhNVDgDkL8f7mpbO/IsV
  G6I1tAHQxMIwCgYIKoZIzj0EAwIDSAAwRQIhANJg4odbZcRiwaCKf0XSty9qDAVH
  SIayVz8kBIBsn63XAiBqlip7nO4QBH8lD4/ZCeg5VR4xfAPCmP0WPoZplycgTIHS
  hEOhASagWFaEYGBggwoDWE2lInggc8/NVYPl3+LqRlN5Zp7+pX9ckLpaIOq8JLqb
  Z3CMeHoheCCuhk9H3dzehSmSvzKXCecYRpf9jNSZWIbH9imm0pcEUSABAQIDJlhA
  W2JW/OTAp2hiU3gG6orEASO6XsBD97yQLbY6lAY80RwfFOEgM4+KiLiCOmYWWxIM
  GMjJyoGICJooh2vZzFbHxA==
  -----END OWNERSHIP VOUCHER-----
  """

  @sample_load_params %{
    data: %{
      "ownership_voucher" => sample_voucher(),
      "key_name" => @sample_key_name,
      "key_algorithm" => "es256"
    }
  }

  setup :verify_on_exit!

  describe "/fdo/ownership_vouchers" do
    setup :register_setup

    test "returns 200 with the owner public key on a valid matching key", context do
      %{auth_conn: conn, register_path: path, realm_name: realm_name} = context

      {:ok, owner_cose_key} = COSE.Keys.from_pem(@sample_private_key_pem)
      {:ok, namespace} = Secrets.create_namespace(realm_name, :es256)
      :ok = Secrets.import_key(@sample_key_name, :es256, owner_cose_key, namespace: namespace)
      {:ok, %Key{public_pem: expected_public_key}} = Secrets.get_key(@sample_key_name, namespace: namespace)

      params = %{
        data: %{
          "ownership_voucher" => @sample_ownership_voucher_pem,
          "key_name" => @sample_key_name,
          "key_algorithm" => "es256"
        }
      }

      body =
        conn
        |> post(path, params)
        |> json_response(200)

      assert get_in(body, ["data", "public_key"]) == expected_public_key
    end

    test "returns 422 when the ownership_voucher field is missing", context do
      %{auth_conn: conn, register_path: path} = context

      params = update_in(@sample_load_params, [:data], &Map.delete(&1, "ownership_voucher"))

      conn
      |> post(path, params)
      |> response(422)
    end

    test "returns 422 when the key_name field is missing", context do
      %{auth_conn: conn, register_path: path} = context

      params = update_in(@sample_load_params, [:data], &Map.delete(&1, "key_name"))

      conn
      |> post(path, params)
      |> response(422)
    end

    test "returns 422 when the key does not exist in the secrets store", context do
      %{auth_conn: conn, register_path: path, realm_name: realm_name} = context

      stub(Secrets, :create_namespace, fn ^realm_name, :es256 ->
        {:ok, "fdo_owner_keys/#{realm_name}/ecdsa-p256"}
      end)

      stub(Secrets, :get_key, fn _name, _opts -> :error end)

      conn
      |> post(path, @sample_load_params)
      |> response(422)
    end

    test "returns 422 when the key public bytes do not match the voucher's last entry", context do
      %{auth_conn: conn, register_path: path, realm_name: realm_name} = context

      wrong_key = %Key{
        name: @sample_key_name,
        namespace: "fdo_owner_keys/#{realm_name}/ecdsa-p256",
        alg: :es256,
        public_pem: """
        -----BEGIN PUBLIC KEY-----
        MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEocPEIHIrn08VRO5zkkDztwp72Sw0
        BSm0mZeLgOKkHLUPdVFFlc0EO82b1/S2Cwzwh8MIDDx0CN2b+IBl5bRwOw==
        -----END PUBLIC KEY-----
        """
      }

      stub(Secrets, :create_namespace, fn ^realm_name, :es256 ->
        {:ok, "fdo_owner_keys/#{realm_name}/ecdsa-p256"}
      end)

      stub(Secrets, :get_key, fn _name, _opts -> {:ok, wrong_key} end)

      conn
      |> post(path, @sample_load_params)
      |> response(422)
    end

    test "returns a 404 error if FDO feature is disabled", context do
      %{auth_conn: conn, register_path: path} = context

      stub(Config, :enable_fdo!, fn -> false end)

      conn
      |> post(path, @sample_load_params)
      |> response(404)
    end
  end

  defp register_setup(context) do
    %{auth_conn: conn, realm_name: realm_name} = context
    register_path = ownership_voucher_path(conn, :register, realm_name)
    %{register_path: register_path}
  end

  describe "/fdo/owner_keys_for_voucher" do
    setup :owner_keys_for_voucher_setup

    test "returns 200 with a map of algorithm to key names", context do
      %{auth_conn: conn, path: path, realm_name: realm_name} = context

      stub(Secrets, :create_namespace, fn ^realm_name, :es256 ->
        {:ok, "fdo_owner_keys/#{realm_name}/ecdsa-p256"}
      end)

      stub(Secrets, :list_keys_names, fn _opts ->
        {:ok, [@sample_key_name, "another_key"]}
      end)

      body =
        conn
        |> post(path, %{data: %{"ownership_voucher" => sample_voucher()}})
        |> json_response(200)

      assert %{"es256" => [@sample_key_name, "another_key"]} = get_in(body, ["data"])
    end

    test "returns 200 with an empty key list when no keys are registered", context do
      %{auth_conn: conn, path: path, realm_name: realm_name} = context

      stub(Secrets, :create_namespace, fn ^realm_name, :es256 ->
        {:ok, "fdo_owner_keys/#{realm_name}/ecdsa-p256"}
      end)

      stub(Secrets, :list_keys_names, fn _opts -> {:ok, []} end)

      body =
        conn
        |> post(path, %{data: %{"ownership_voucher" => sample_voucher()}})
        |> json_response(200)

      assert %{"es256" => []} = get_in(body, ["data"])
    end

    test "returns 422 when the ownership_voucher field is missing", context do
      %{auth_conn: conn, path: path} = context

      conn
      |> post(path, %{data: %{}})
      |> response(422)
    end

    test "returns 404 when the FDO feature is disabled", context do
      %{auth_conn: conn, path: path} = context

      stub(Config, :enable_fdo!, fn -> false end)

      conn
      |> post(path, %{data: %{"ownership_voucher" => sample_voucher()}})
      |> response(404)
    end
  end

  defp owner_keys_for_voucher_setup(context) do
    %{auth_conn: conn, realm_name: realm_name} = context
    path = ownership_voucher_path(conn, :owner_keys_for_voucher, realm_name)
    %{path: path}
  end
end
