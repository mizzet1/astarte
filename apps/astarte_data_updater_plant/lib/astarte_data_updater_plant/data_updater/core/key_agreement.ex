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

defmodule Astarte.DataUpdaterPlant.DataUpdater.Core.KeyAgreement do
  @moduledoc """
  Key agreement messages that both the control and the data handlers send to a device.
  """
  alias Astarte.Core.Device
  alias Astarte.DataUpdaterPlant.DataUpdater.Core.KeyAgreement.ExchangeFailed
  alias Astarte.DataUpdaterPlant.RPC.VMQPlugin

  require Logger

  @doc """
  Publishes an `ExchangeFailed` message to a device on:
  `<realm>/<device_id>/control/keyAgreement/4`

  Besides replying to a failed handshake step, Astarte sends it to ask the device
  for a new handshake, for example when an encrypted payload can't be decrypted.
  """
  @spec send_exchange_failed(
          String.t(),
          binary(),
          non_neg_integer(),
          ExchangeFailed.reason(),
          String.t()
        ) ::
          :ok | {:error, term()}
  def send_exchange_failed(realm, device_id, seq_num, reason, error_msg) do
    :telemetry.execute(
      [:astarte, :data_updater_plant, :device_key_agreement, :failed],
      %{},
      %{realm: realm, reason: reason}
    )

    topic = "#{realm}/#{Device.encode_device_id(device_id)}/control/keyAgreement/4"

    {:ok, exchange_failed} = ExchangeFailed.new(seq_num, reason, error_msg)
    payload = ExchangeFailed.cbor_encode(exchange_failed)

    publish_start = System.monotonic_time()

    case VMQPlugin.publish(topic, payload, 2) do
      {:ok, %{local_matches: local, remote_matches: remote}} when local + remote >= 1 ->
        :telemetry.execute(
          [:astarte, :data_updater_plant, :control_handler, :key_agreement_exchange_failed_send],
          %{
            duration: System.monotonic_time() - publish_start,
            payload_size: byte_size(payload)
          },
          %{realm: realm, result: "success", reason: reason}
        )

        :ok

      {:ok, %{local_matches: 0, remote_matches: 0}} ->
        :telemetry.execute(
          [:astarte, :data_updater_plant, :control_handler, :key_agreement_exchange_failed_send],
          %{
            duration: System.monotonic_time() - publish_start,
            payload_size: byte_size(payload)
          },
          %{realm: realm, result: "no_matches", reason: reason}
        )

        Logger.warning(
          "[keyAgreement/4] Could not deliver ExchangeFailed (#{inspect(reason)}): device session not found",
          tag: "exchange_failed_no_session"
        )

        {:error, :session_not_found}

      {:error, publish_reason} ->
        :telemetry.execute(
          [:astarte, :data_updater_plant, :control_handler, :key_agreement_exchange_failed_send],
          %{
            duration: System.monotonic_time() - publish_start,
            payload_size: byte_size(payload)
          },
          %{realm: realm, result: "error", reason: reason}
        )

        Logger.warning(
          "[keyAgreement/4] Could not deliver ExchangeFailed (#{inspect(reason)}): #{inspect(publish_reason)}",
          tag: "exchange_failed_publish_error"
        )

        {:error, publish_reason}
    end
  end
end
