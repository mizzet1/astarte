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

defmodule Astarte.DataUpdaterPlant.DataUpdater.Core.KeyAgreement.HashOk do
  @moduledoc """
  Represents the HashOk (type 3) key-agreement message published on the
  `<realm>/<device>/control/keyAgreement/3` MQTT control topic.
  """

  use TypedStruct

  alias __MODULE__, as: HashOk
  alias Astarte.DataUpdaterPlant.DataUpdater.Core.KeyAgreement.InitExchange

  typedstruct enforce: true do
    @typedoc "HashOk acknowledgement message containing the key-suite algorithm code."
    field :key_type, non_neg_integer()
  end

  @doc """
  Builds a new `%HashOk{}` mapping the internal algorithm atom to its RFC integer value.
  """

  @spec new(InitExchange.key_suite() | non_neg_integer()) :: t()
  def new(:ecdh_p256_hkdf_sha256_aes_256_gcm), do: %HashOk{key_type: 0}
  def new(:ecdh_x25519_hkdf_sha256_aes_256_gcm), do: %HashOk{key_type: 1}
  def new(key_type) when is_integer(key_type) and key_type >= 0, do: %HashOk{key_type: key_type}
  @spec encode(t()) :: list()
  def encode(%HashOk{} = msg), do: [msg.key_type]
  @spec cbor_encode(t()) :: binary()
  def cbor_encode(%HashOk{} = msg), do: msg |> encode() |> CBOR.encode()

  @doc """
  Decodes and validates a raw CBOR payload received on the
  `control/keyAgreement/3` topic.
  """
  @spec cbor_decode(binary()) :: {:ok, t()} | {:error, :invalid_payload}
  def cbor_decode(payload) when is_binary(payload) do
    case CBOR.decode(payload) do
      {:ok, raw, _rest} -> decode(raw)
      {:error, _reason} -> {:error, :invalid_payload}
    end
  end

  defp decode([key_type]) when is_integer(key_type) and key_type >= 0 do
    {:ok, %HashOk{key_type: key_type}}
  end

  defp decode(_), do: {:error, :invalid_payload}
end
