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

defmodule Astarte.DataUpdaterPlant.DataUpdater.Core.KeyAgreement.HashOkTest do
  use ExUnit.Case, async: true

  alias Astarte.DataUpdaterPlant.DataUpdater.Core.KeyAgreement.HashOk

  describe "new/1" do
    test "maps :ecdh_p256_hkdf_sha256_aes_256_gcm to key_type 0" do
      msg = HashOk.new(:ecdh_p256_hkdf_sha256_aes_256_gcm)

      assert %HashOk{} = msg
      assert msg.key_type == 0
    end

    test "maps :ecdh_x25519_hkdf_sha256_aes_256_gcm to key_type 1" do
      msg = HashOk.new(:ecdh_x25519_hkdf_sha256_aes_256_gcm)

      assert %HashOk{} = msg
      assert msg.key_type == 1
    end

    test "accepts non-negative integers directly" do
      for key_type <- [0, 1, 42, 255] do
        msg = HashOk.new(key_type)

        assert %HashOk{} = msg
        assert msg.key_type == key_type
      end
    end
  end

  describe "encode/1" do
    test "returns a single-element list with the key_type" do
      msg = HashOk.new(1)
      assert HashOk.encode(msg) == [1]

      msg_zero = HashOk.new(0)
      assert HashOk.encode(msg_zero) == [0]
    end
  end

  describe "cbor_encode/1" do
    test "encodes the struct into a valid CBOR binary" do
      msg = HashOk.new(1)
      encoded = HashOk.cbor_encode(msg)

      assert is_binary(encoded)

      assert {:ok, [1], ""} = CBOR.decode(encoded)
    end
  end

  describe "cbor_decode/1" do
    test "successfully decodes a valid CBOR payload" do
      payload = CBOR.encode([1])
      assert {:ok, %HashOk{key_type: 1}} = HashOk.cbor_decode(payload)

      payload_zero = CBOR.encode([0])
      assert {:ok, %HashOk{key_type: 0}} = HashOk.cbor_decode(payload_zero)
    end

    test "returns error for valid CBOR with invalid inner structure" do
      invalid_payloads = [
        # Not a list
        CBOR.encode("not a list"),
        # Empty list
        CBOR.encode([]),
        # List with negative integer
        CBOR.encode([-1]),
        # List with non-integer
        CBOR.encode(["string"]),
        # List with too many elements
        CBOR.encode([1, 2])
      ]

      for payload <- invalid_payloads do
        assert {:error, :invalid_payload} = HashOk.cbor_decode(payload)
      end
    end

    test "returns error for invalid malformed CBOR binary" do
      # <<0xFF>> is an invalid starting byte for CBOR, forcing an error
      invalid_cbor = <<0xFF>>
      assert {:error, :invalid_payload} = HashOk.cbor_decode(invalid_cbor)
    end
  end
end
