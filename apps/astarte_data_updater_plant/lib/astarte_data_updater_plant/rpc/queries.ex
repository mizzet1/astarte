defmodule Astarte.DataUpdaterPlant.RPC.Queries do
  import Ecto.Query
  alias Astarte.DataAccess.Consistency
  alias Astarte.DataAccess.Realms.Realm
  alias Astarte.DataAccess.Repo
  alias Astarte.DataAccess.Devices.Device
  require Logger

  def fetch_connected_devices(realm_name) do
    keyspace = Realm.keyspace_name(realm_name)

    query =
      from(Device,
        hints: ["ALLOW FILTERING"],
        where: [connected: true],
        select: [:device_id, :groups]
      )

    consistency = Consistency.domain_model(:read)
    Repo.fetch_all(query, prefix: keyspace, consistency: consistency)
  end

  def fetch_realms! do
    keyspace = Realm.astarte_keyspace_name()
    query = from(realm in "realms", select: realm.realm_name)
    consistency = Consistency.domain_model(:read)
    Repo.fetch_all(query, prefix: keyspace, consistency: consistency)
  end
end
