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
# SPDX-License-Identifier: Apache-2.0
#

defmodule Astarte.DataUpdaterPlant.DataUpdater.Core.KeyAgreement.HandshakeStateTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Astarte.DataUpdaterPlant.DataUpdater.Core.KeyAgreement.HandshakeState
  alias Astarte.DataUpdaterPlant.DataUpdater.Core.KeyAgreement.InitExchange

  setup do
    init_exchange = InitExchange.new(0)

    %{
      secret: :crypto.strong_rand_bytes(32),
      init_exchange: init_exchange,
      started:
        {:handshake_started, %{key_type: init_exchange.key_type, init_exchange: init_exchange}}
    }
  end

  describe "name/1" do
    test "returns the name of every state without its data", context do
      %{secret: secret, started: started} = context

      assert HandshakeState.name(:uninitialized) == :uninitialized
      assert HandshakeState.name(started) == :handshake_started
      assert HandshakeState.name(HandshakeState.restore(secret)) == :established
      assert HandshakeState.name({:failed, :invalid_argument}) == :failed
    end
  end

  describe "transition/2 with {:receive_init, msg}" do
    test "starts a new handshake from every state", context do
      %{secret: secret, init_exchange: init_exchange, started: started} = context

      expected =
        {:handshake_started, %{key_type: init_exchange.key_type, init_exchange: init_exchange}}

      for current_state <- [
            :uninitialized,
            started,
            HandshakeState.restore(secret),
            {:failed, :invalid_argument}
          ] do
        assert {:ok, ^expected} =
                 HandshakeState.transition(current_state, {:receive_init, init_exchange})
      end
    end

    test "rotates an established key once the new handshake completes", context do
      %{secret: old_secret, init_exchange: init_exchange} = context
      new_secret = :crypto.strong_rand_bytes(32)

      assert {:ok, started} =
               HandshakeState.restore(old_secret)
               |> HandshakeState.transition({:receive_init, init_exchange})

      assert {:ok, {:established, %{shared_secret: ^new_secret}}} =
               HandshakeState.transition(started, {:handshake_completed, new_secret})
    end
  end

  describe "transition/2 with an invalid event" do
    test "doesn't log the shared secret held by the established state", %{secret: secret} do
      log =
        capture_log(fn ->
          assert {:error, :unprocessable_entity, "invalid transition"} =
                   HandshakeState.transition(
                     HandshakeState.restore(secret),
                     {:handshake_completed, secret}
                   )
        end)

      assert log =~ "from state :established"
      refute log =~ inspect(secret)
      refute log =~ "shared_secret"
    end

    test "doesn't log the shared secret carried by the event", %{secret: secret} do
      log =
        capture_log(fn ->
          assert {:error, :unprocessable_entity, "invalid transition"} =
                   HandshakeState.transition(:uninitialized, {:handshake_completed, secret})
        end)

      assert log =~ "with event :handshake_completed from state :uninitialized"
      refute log =~ inspect(secret)
    end
  end
end
