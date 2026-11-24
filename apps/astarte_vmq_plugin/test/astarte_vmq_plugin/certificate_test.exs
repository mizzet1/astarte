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

defmodule Astarte.VMQ.Plugin.CertificateTest do
  use ExUnit.Case, async: true

  alias Astarte.VMQ.Plugin.Certificate
  alias Astarte.VMQ.Plugin.Test.Fixtures.Device, as: DeviceFixture

  test "serial_and_aki/1 returns the identifiers in the format Pairing stores them" do
    assert Certificate.serial_and_aki(DeviceFixture.client_crt_der()) ==
             {DeviceFixture.client_crt_serial(), DeviceFixture.client_crt_aki()}
  end
end
