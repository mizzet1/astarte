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

defmodule Astarte.RPC.VolatileTriggers do
  @moduledoc """
  Functions to operate on triggers
  """

  alias Astarte.Core.Triggers.SimpleTriggersProtobuf.AMQPTriggerTarget
  alias Astarte.Core.Triggers.SimpleTriggersProtobuf.TaggedSimpleTrigger
  alias Astarte.Events.Triggers.Core, as: EventsCore
  alias Astarte.RPC.Server
  alias Astarte.RPC.Triggers.Core
  alias Astarte.RPC.VolatileTriggers.VolatileTriggerDeletion
  alias Astarte.RPC.VolatileTriggers.VolatileTriggerInstallation
  alias Phoenix.PubSub

  @all_key "volatile-triggers:*"
  @deletion_key "volatile-triggers:deletion"

  def subscribe_all, do: PubSub.subscribe(Server, @all_key)

  @doc """
  Subscribes the current process to the installation of volatile triggers of the
  given types only.

  Deletion messages carry just the trigger id, so the type of the deleted
  trigger is not known when they are broadcast: subscribers of any type receive
  every deletion, and deleting an unknown trigger is a no-op.
  """
  def subscribe_types([]), do: :ok

  def subscribe_types(types) do
    for type <- types do
      key = volatile_trigger_by_type_key(type)
      PubSub.subscribe(Server, key)
    end

    PubSub.subscribe(Server, @deletion_key)
  end

  @spec install(
          String.t(),
          TaggedSimpleTrigger.t(),
          AMQPTriggerTarget.t(),
          EventsCore.fetch_triggers_data()
        ) :: :ok | {:error, term()}
  def install(realm_name, tagged_simple_trigger, target, data \\ %{}) do
    with {:ok, data} <- Core.find_trigger_data(realm_name, tagged_simple_trigger, data) do
      message =
        %VolatileTriggerInstallation{
          realm_name: realm_name,
          simple_trigger: tagged_simple_trigger,
          target: target,
          data: data
        }

      broadcast(to_volatile_trigger_by_type_key(tagged_simple_trigger), message)
    end
  end

  @spec delete(String.t(), Astarte.DataAccess.UUID.t()) :: :ok | {:error, term()}
  def delete(realm_name, trigger_id) do
    message =
      %VolatileTriggerDeletion{
        realm_name: realm_name,
        trigger_id: trigger_id
      }

    broadcast(@deletion_key, message)
  end

  defp broadcast(key, message) do
    PubSub.broadcast(Server, key, message)
    PubSub.broadcast(Server, @all_key, message)
  end

  defp to_volatile_trigger_by_type_key(tagged_simple_trigger) do
    trigger_type = trigger_type(tagged_simple_trigger.simple_trigger_container.simple_trigger)

    volatile_trigger_by_type_key(trigger_type)
  end

  defp volatile_trigger_by_type_key(trigger_type) do
    "volatile-trigger-by-type:" <> Atom.to_string(trigger_type)
  end

  defp trigger_type({:device_trigger, device_trigger}), do: device_trigger.device_event_type
  defp trigger_type({:data_trigger, data_trigger}), do: data_trigger.data_trigger_type
end
