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
# SPDX-License-Identifier: Apache-2.0
#

defmodule Astarte.DataUpdaterPlant.RPC.Server do
  @moduledoc """
  This server receives incoming calls from other astarte services and queues the
  calls to the appropriate dup services to handle the calls.
  """

  alias Astarte.DataUpdaterPlant.RPC.Core.StateHandler
  alias Astarte.DataUpdaterPlant.RPC.Core.Trigger
  alias Astarte.DataUpdaterPlant.RPC.State

  use GenServer, restart: :transient
  require Logger

  def start_link(args, opts \\ []) do
    name = {:via, Horde.Registry, {Registry.DataUpdaterRPC, :server}}
    opts = Keyword.put(opts, :name, name)

    GenServer.start_link(__MODULE__, args, opts)
  end

  @impl GenServer
  def init(_args) do
    Process.flag(:trap_exit, true)

    state = %State{
      devices: %{}
    }

    {:ok, state}
  end

  @impl GenServer
  def handle_info(
        {:EXIT, _pid, {:name_conflict, {_name, _value}, _registry, _winning_pid}},
        state
      ) do
    _ =
      Logger.warning(
        "Received a :name_confict signal from the outer space, maybe a netsplit occurred? Gracefully shutting down.",
        tag: "RPC exit"
      )

    {:stop, :shutdown, state}
  end

  @impl GenServer
  def handle_info({:EXIT, _pid, :shutdown}, state) do
    _ =
      Logger.warning(
        "Received a :shutdown signal from the outer space, maybe the supervisor is mad? Gracefully shutting down.",
        tag: "RPC exit"
      )

    {:stop, :shutdown, state}
  end

  @impl GenServer
  def handle_call({:install_persistent_triggers, triggers}, _from, state) do
    Trigger.install_persistent_triggers(triggers, state)
  end

  @impl GenServer
  def handle_call({:add_device, device}, _from, state) do
    Logger.debug(
      "handle_call :add_device called with state: #{inspect(state)}, device: #{inspect(device)}"
    )

    new_state = StateHandler.add_device(state, device)
    Logger.debug("New state after adding device: #{inspect(new_state)}")

    {:reply, :ok, new_state}
  end

  @impl GenServer
  def handle_call({:remove_device, device_id, realm}, _from, state) do
    new_state = StateHandler.remove_device(state, device_id, realm)
    {:reply, :ok, new_state}
  end

  @impl GenServer
  def handle_call({:update_device_groups, device_id, realm, groups}, _from, state) do
    new_state = StateHandler.update_device_groups(state, device_id, realm, groups)
    {:reply, :ok, new_state}
  end
end
