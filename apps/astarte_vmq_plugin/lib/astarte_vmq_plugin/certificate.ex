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

defmodule Astarte.VMQ.Plugin.Certificate do
  @moduledoc """
  Extracts the identifiers Pairing stores for the certificates it issues.
  """

  require Record

  @public_key_hrl "public_key/include/public_key.hrl"

  Record.defrecordp(
    :otp_certificate,
    :OTPCertificate,
    Record.extract(:OTPCertificate, from_lib: @public_key_hrl)
  )

  Record.defrecordp(
    :otp_tbs_certificate,
    :OTPTBSCertificate,
    Record.extract(:OTPTBSCertificate, from_lib: @public_key_hrl)
  )

  Record.defrecordp(:extension, :Extension, Record.extract(:Extension, from_lib: @public_key_hrl))

  Record.defrecordp(
    :authority_key_identifier,
    :AuthorityKeyIdentifier,
    Record.extract(:AuthorityKeyIdentifier, from_lib: @public_key_hrl)
  )

  @aki_oid {2, 5, 29, 35}

  @doc """
  Returns the serial number and the authority key identifier of a DER certificate,
  in the same format Pairing saves them in the devices table.
  """
  @spec serial_and_aki(binary()) :: {String.t(), String.t() | nil}
  def serial_and_aki(der) do
    tbs =
      der
      |> :public_key.pkix_decode_cert(:otp)
      |> otp_certificate(:tbsCertificate)

    serial = tbs |> otp_tbs_certificate(:serialNumber) |> Integer.to_string()
    {serial, aki(otp_tbs_certificate(tbs, :extensions))}
  end

  defp aki(extensions) when is_list(extensions) do
    Enum.find_value(extensions, fn
      extension(extnID: @aki_oid, extnValue: value) ->
        case authority_key_identifier(value, :keyIdentifier) do
          key_id when is_binary(key_id) -> Base.encode16(key_id, case: :lower)
          _ -> nil
        end

      _ ->
        nil
    end)
  end

  defp aki(_), do: nil
end
