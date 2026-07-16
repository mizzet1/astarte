defmodule Astarte.PairingWeb.GraphQL.Resolvers.DeviceManagerResolver do
  alias Astarte.PairingWeb.GraphQL.OpenFGAClient

  @doc """
  Grants a user the `device_manager` relation on the current realm. Device
  managers inherit `can_unregister`/`can_obtain_credentials`/`can_verify_credentials`
  on every device belonging to the realm, via the `device_manager from belongs_to`
  composed relation in the OpenFGA authorization model.
  Authorization is enforced upstream by the AuthorizeFGA middleware.
  """
  def grant_device_manager(_parent, %{user_id: user_id}, %{context: context}) do
    realm = Map.fetch!(context, :realm_name)

    case OpenFGAClient.write_tuple("user:#{user_id}", "device_manager", "realm:#{realm}") do
      :ok -> {:ok, "Granted device_manager on #{realm} to #{user_id}"}
      {:error, reason} -> {:error, "Failed to grant device_manager: #{inspect(reason)}"}
    end
  end

  @doc """
  Revokes a user's `device_manager` relation on the current realm.
  Authorization is enforced upstream by the AuthorizeFGA middleware.
  """
  def revoke_device_manager(_parent, %{user_id: user_id}, %{context: context}) do
    realm = Map.fetch!(context, :realm_name)

    case OpenFGAClient.delete_tuple("user:#{user_id}", "device_manager", "realm:#{realm}") do
      :ok -> {:ok, "Revoked device_manager on #{realm} from #{user_id}"}
      {:error, reason} -> {:error, "Failed to revoke device_manager: #{inspect(reason)}"}
    end
  end

  @doc """
  Lists the devices the current user can manage, either via a direct
  device-level grant or by inheriting it as a realm device manager. This is
  answered entirely by OpenFGA's ListObjects, without checking devices
  one by one.
  """
  def manageable_devices(_parent, _args, %{context: context}) do
    case OpenFGAClient.resolve_user_id(Map.get(context, :current_user)) do
      nil ->
        {:error, "Unauthorized: Missing valid user session"}

      user_id ->
        case OpenFGAClient.list_objects("user:#{user_id}", "can_unregister", "device") do
          {:ok, objects} -> {:ok, Enum.map(objects, &strip_type_prefix/1)}
          {:error, reason} -> {:error, "Failed to list manageable devices: #{inspect(reason)}"}
        end
    end
  end

  defp strip_type_prefix("device:" <> hw_id), do: hw_id
  defp strip_type_prefix(object), do: object
end
