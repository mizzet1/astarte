#
# This file is part of Astarte.
#
# Copyright 2025 - 2026 SECO Mind Srl
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

defmodule Astarte.VMQ.Plugin.Test.Fixtures.Device do
  @moduledoc "Device fixtures: an invalid device id and a client certificate."
  def not_a_device_id, do: "I am not a device"

  @client_crt """
  -----BEGIN CERTIFICATE-----
  MIIBbTCCAROgAwIBAgIIHSw7Sllod2YwCgYIKoZIzj0EAwIwEjEQMA4GA1UEAwwH
  VGVzdCBDQTAgFw0yNjExMjQxMzUzNDZaGA8yMTI2MTAzMTEzNTM0NlowFjEUMBIG
  A1UEAwwLdGVzdC9kZXZpY2UwWTATBgcqhkjOPQIBBggqhkjOPQMBBwNCAAQRw+I1
  50LfahW/DcgXSoTyvOWSNECA1PWWQ9qOGM5L9O+OcxyVI1jjRVkwNKl1ZSGJ201Z
  b6Pa3+oQxO7o7It2o00wSzAfBgNVHSMEGDAWgBRKRtX7gLAGJNxfJFgFm/dBSIbp
  8zAJBgNVHRMEAjAAMB0GA1UdDgQWBBSqXp11m/jUXm+ywPg7X/9gUu22UjAKBggq
  hkjOPQQDAgNIADBFAiAyi/K2HNw3DFZCb14OEuxQiAzvkeWGuHWotT1dz3aU2AIh
  AI0uo2m2YAf4g5VWPXqNGw6tMQoc3oOglBi7jXp1gdY4
  -----END CERTIFICATE-----
  """

  @doc "DER client certificate, as VerneMQ forwards it"
  def client_crt_der do
    [{:Certificate, der, :not_encrypted}] = :public_key.pem_decode(@client_crt)
    der
  end

  # Values from `openssl x509 -serial -ext authorityKeyIdentifier`, in Pairing's format
  def client_crt_serial, do: "2102120316588816230"
  def client_crt_aki, do: "4a46d5fb80b00624dc5f2458059bf7414886e9f3"
end
