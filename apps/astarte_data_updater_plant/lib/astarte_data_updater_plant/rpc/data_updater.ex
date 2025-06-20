defmodule Astarte.DataUpdaterPlant.RPC.DataUpdater do
  defp server_via_tuple(), do: {:via, Horde.Registry, {Registry.DataUpdaterRPC, :server}}

  def add_device(device) do
    server_via_tuple()
    |> GenServer.call({:add_device, device})
  end

  def remove_device(device_id, realm) do
    server_via_tuple()
    |> GenServer.call({:remove_device, device_id, realm})
  end

  def update_device_groups(device_id, realm, groups) do
    server_via_tuple()
    |> GenServer.call({:update_device_groups, device_id, realm, groups})
  end
end
