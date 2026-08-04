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

defmodule Astarte.DataUpdaterPlant.DataUpdater.Core.IntrospectionRootCauseTest do
  @moduledoc """
  Root-cause investigation for the production issue: a device's introspection
  becomes empty after a while.

  Every test below owns its OWN, uniquely-generated device row so tests never
  contaminate each other (important: ExUnit randomizes test order). Each test
  drives real production functions against the real Cassandra/Scylla + real
  Mississippi/RabbitMQ plumbing already available in this environment -
  nothing here is mocked unless explicitly noted.
  """

  use Astarte.Cases.Data, async: true

  use Mimic

  alias Astarte.DataAccess.Devices.Device, as: DatabaseDevice
  alias Astarte.DataAccess.Realms.Realm
  alias Astarte.DataAccess.Repo
  alias Astarte.DataUpdaterPlant.DataUpdater.Core
  alias Astarte.DataUpdaterPlant.DataUpdater.Impl
  alias Astarte.DataUpdaterPlant.DataUpdater.Queries
  alias Astarte.DataUpdaterPlant.TriggersHandler

  setup %{realm_name: realm_name} do
    device_id = :crypto.strong_rand_bytes(16)
    keyspace = Realm.keyspace_name(realm_name)

    device_row = %DatabaseDevice{
      device_id: device_id,
      introspection: %{"com.test.OldInterfaceOne" => 1, "com.test.OldInterfaceTwo" => 3},
      introspection_minor: %{"com.test.OldInterfaceOne" => 0, "com.test.OldInterfaceTwo" => 2},
      total_received_msgs: 0,
      total_received_bytes: 0,
      exchanged_bytes_by_interface: %{},
      exchanged_msgs_by_interface: %{}
    }

    Repo.insert!(device_row, prefix: keyspace)

    %{device_id: device_id, keyspace: keyspace}
  end

  describe "Mechanism: how does an all-empty introspection write actually behave?" do
    test "Queries.update_device_introspection!/4 SILENTLY NO-OPS when writing an empty map, leaving stale old data in the DB",
         %{realm_name: realm_name, device_id: device_id, keyspace: keyspace} do
      before_row = Repo.get!(DatabaseDevice, device_id, prefix: keyspace)
      assert map_size(before_row.introspection) == 2

      # This is the exact call process_introspection/4 makes at device.ex:144-149
      # when a device's new introspection is empty.
      Queries.update_device_introspection!(realm_name, device_id, %{}, %{})

      after_row = Repo.get!(DatabaseDevice, device_id, prefix: keyspace)

      IO.puts(
        "\n[mechanism evidence] introspection column before: #{inspect(before_row.introspection)}, after writing %{}: #{inspect(after_row.introspection)}\n"
      )

      assert after_row.introspection == before_row.introspection,
             "the DB write for an empty introspection map is a no-op: old data survives untouched"
    end

    test "root cause: Ecto.Changeset.change/2 sees NO CHANGE when going from a blank struct's nil to %{}, because Exandra.Map.equal?(nil, %{}) == true",
         %{device_id: device_id} do
      # This mirrors exactly what Queries.update_device_introspection!/4 does:
      # it builds the changeset off a freshly-constructed, blank struct instead
      # of the row actually persisted in the DB.
      blank_struct_changeset =
        %DatabaseDevice{device_id: device_id}
        |> Ecto.Changeset.change(introspection: %{}, introspection_minor: %{})

      refute Map.has_key?(blank_struct_changeset.changes, :introspection),
             "Ecto considers nil (blank struct default) and %{} equivalent for the Exandra.Map type, so it drops the field from the changeset entirely"

      # Prove it's specifically the blank-struct comparison at fault: if we
      # build the changeset from a struct that actually carries the current
      # (non-empty) persisted value, Ecto correctly detects the change.
      populated_struct_changeset =
        %DatabaseDevice{device_id: device_id, introspection: %{"com.test.OldInterfaceOne" => 1}}
        |> Ecto.Changeset.change(introspection: %{})

      assert Map.get(populated_struct_changeset.changes, :introspection) == %{},
             "when the comparison baseline is the real current value, Ecto DOES detect the change to empty"
    end

    test "closing the loop: when the changeset IS built from the real current row, what does Cassandra actually store for an empty map?",
         %{device_id: device_id, keyspace: keyspace} do
      current_row = Repo.get!(DatabaseDevice, device_id, prefix: keyspace)
      assert map_size(current_row.introspection) == 2

      changeset = Ecto.Changeset.change(current_row, introspection: %{}, introspection_minor: %{})
      assert Map.has_key?(changeset.changes, :introspection)

      Repo.update!(changeset, prefix: keyspace, consistency: :quorum)

      after_row = Repo.get!(DatabaseDevice, device_id, prefix: keyspace)

      IO.puts(
        "\n[true empty-write evidence] introspection after a REAL (non-skipped) empty-map write: #{inspect(after_row.introspection)}\n"
      )

      assert after_row.introspection == %{},
             "when the write actually reaches Cassandra, Exandra's load/3 normalizes the resulting NULL column back to %{} on read - so a genuine empty write is safe and correctly observable as empty"
    end
  end

  describe "Practical consequence of the silent no-op" do
    test "after a device sends an empty introspection payload, the LIVE in-memory device state goes empty while the DB keeps the stale old introspection",
         %{realm_name: realm_name, device_id: device_id, keyspace: keyspace} do
      sharding_key = {realm_name, device_id}
      data_updater = start_supervised!({Mississippi.Consumer.DataUpdater, sharding_key: sharding_key})

      Mimic.allow(Astarte.DataAccess.Config, self(), data_updater)
      Mimic.allow(Impl, self(), data_updater)

      {:ok, handler_state} = Impl.init(sharding_key)
      :sys.replace_state(data_updater, fn state -> %{state | message_handler: Impl, handler_state: handler_state} end)

      assert map_size(handler_state.introspection) == 2

      final_state = Core.Device.process_introspection(handler_state, [], "", 0) |> elem(2)

      assert final_state.introspection == %{},
             "in-memory state DOES go empty: the final_state override at device.ex:157-159 is unconditional"

      db_row = Repo.get!(DatabaseDevice, device_id, prefix: keyspace)

      assert map_size(db_row.introspection) == 2,
             "meanwhile the DB retains the stale pre-wipe introspection, because the write silently no-op'd"

      refute final_state.introspection == db_row.introspection,
             "in-memory (device process) and on-disk (Cassandra) introspection have now permanently diverged for this process's lifetime"
    end

    test "a device that legitimately drops to a SMALLER non-empty introspection is NOT affected by this bug (only the fully-empty case is)",
         %{realm_name: realm_name, device_id: device_id, keyspace: keyspace} do
      {:ok, state} = Impl.init({realm_name, device_id})

      new_introspection = [{"com.test.OldInterfaceOne", 1, 0}]
      payload = "com.test.OldInterfaceOne:1:0"

      {:ack, :ok, final_state} = Core.Device.process_introspection(state, new_introspection, payload, 0)

      assert final_state.introspection == %{"com.test.OldInterfaceOne" => 1}

      db_row = Repo.get!(DatabaseDevice, device_id, prefix: keyspace)

      assert db_row.introspection == %{"com.test.OldInterfaceOne" => 1},
             "a non-empty resulting map is written correctly - the bug is specific to the all-empty case"
    end
  end

  describe "Finding: the 3-write introspection update is not atomic" do
    test "a transient Cassandra failure between the writes crashes the process AFTER triggers fire but BEFORE the introspection column is touched",
         %{realm_name: realm_name, device_id: device_id, keyspace: keyspace} do
      {:ok, state} = Impl.init({realm_name, device_id})
      introspection_before = state.introspection

      test_pid = self()

      expect(TriggersHandler, :incoming_introspection, fn _realm, _device_id, _groups, _payload, _ts ->
        send(test_pid, :trigger_fired)
        :ok
      end)

      expect(Queries, :add_old_interfaces, fn _realm, _device_id, _old_interfaces ->
        {:error, :timeout}
      end)

      reject(&Queries.update_device_introspection!/4)

      new_introspection_list = [{"com.test.NewInterface", 1, 0}]

      assert_raise MatchError, fn ->
        Core.Device.process_introspection(state, new_introspection_list, "com.test.NewInterface:1:0", 0)
      end

      assert_received :trigger_fired,
                       "the incoming_introspection trigger already fired before the crash"

      db_row = Repo.get!(DatabaseDevice, device_id, prefix: keyspace)

      assert db_row.introspection == introspection_before,
             "the introspection column must be untouched: the crash happened before update_device_introspection! ran"
    end
  end

  describe "Sanity check: can State.introspection ever actually be nil via the normal read path?" do
    test "Queries.get_device_status/2 normalizes a genuinely-NULL DB column to %{}, via Exandra.Map's load/3 callback",
         %{realm_name: realm_name, keyspace: keyspace} do
      # A device row that has NEVER had introspection set (truly NULL column,
      # not an empty-map-that-should-have-been-null).
      never_introspected_id = :crypto.strong_rand_bytes(16)

      Repo.insert!(
        %DatabaseDevice{
          device_id: never_introspected_id,
          total_received_msgs: 0,
          total_received_bytes: 0,
          exchanged_bytes_by_interface: %{},
          exchanged_msgs_by_interface: %{}
        },
        prefix: keyspace
      )

      raw_row = Repo.get!(DatabaseDevice, never_introspected_id, prefix: keyspace)
      assert raw_row.introspection == %{},
             "Ecto/Exandra's load/3 already normalizes nil -> %{} on every read through the schema"

      status = Queries.get_device_status(realm_name, never_introspected_id)
      assert status.introspection == %{}

      {:ok, state} = Impl.init({realm_name, never_introspected_id})
      assert state.introspection == %{},
             "State.introspection can NOT actually become nil through the normal init path - this hypothesis is refuted"
    end
  end
end
