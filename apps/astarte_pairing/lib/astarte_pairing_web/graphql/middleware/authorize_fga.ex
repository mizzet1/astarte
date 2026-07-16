defmodule Astarte.PairingWeb.GraphQL.Middleware.AuthorizeFGA do
  @behaviour Absinthe.Middleware

  alias Astarte.Pairing.Config
  alias Astarte.PairingWeb.GraphQL.Auth, as: GraphQLAuth
  alias Astarte.PairingWeb.GraphQL.OpenFGAClient
  require Logger

  def call(resolution, opts) do
    if Config.authentication_disabled?() do
      resolution
    else
      do_authorize(resolution, opts)
    end
  end

  defp do_authorize(resolution, opts) do
    context = resolution.context

    # OpenFGA arguments
    relation = Keyword.fetch!(opts, :relation)
    target_type = Keyword.fetch!(opts, :target)

    # fallback legacy arguments for when OpenFGA is not configured
    legacy_method = Keyword.get(opts, :legacy_method)
    legacy_path_fn = Keyword.get(opts, :legacy_path_fn)

    store_id = OpenFGAClient.store_id()

    if is_nil(store_id) or store_id == "" do
      # FALLBACK LEGACY: OpenFga is not configured, fallback to legacy authorization
      legacy_path =
        if is_function(legacy_path_fn),
          do: legacy_path_fn.(resolution.arguments),
          else: Keyword.get(opts, :legacy_path)

      case GraphQLAuth.authorize_from_context(context, legacy_method, legacy_path) do
        :ok -> resolution
        {:error, msg} -> Absinthe.Resolution.put_result(resolution, {:error, msg})
      end
    else
      user = Map.get(context, :current_user)
      Logger.info("==> [OpenFGA] Current user from context: #{inspect(user)}")

      user_id = OpenFGAClient.resolve_user_id(user)

      Logger.info(
        "==> [OpenFGA] Authorizing user_id: #{inspect(user_id)} for relation: #{relation} on target_type: #{target_type}"
      )

      with {:user, uid} when not is_nil(uid) <- {:user, user_id},
           {:realm, realm_name} when not is_nil(realm_name) <-
             {:realm, Map.get(context, :realm_name)},
           :ok <-
             check_openfga(uid, relation, target_type, realm_name, resolution.arguments) do
        resolution
      else
        {:user, _} ->
          Absinthe.Resolution.put_result(
            resolution,
            {:error, "Unauthorized: Missing valid user session"}
          )

        {:realm, _} ->
          Absinthe.Resolution.put_result(
            resolution,
            {:error, "Unauthorized: Missing realm context"}
          )

        {:error, :forbidden} ->
          Absinthe.Resolution.put_result(
            resolution,
            {:error, "Forbidden: OpenFGA denied access for this action"}
          )

        {:error, reason} ->
          Logger.error("OpenFGA Check failed: #{inspect(reason)}")

          Absinthe.Resolution.put_result(
            resolution,
            {:error, "Internal Server Error during authorization"}
          )
      end
    end
  end

  # Builds the OpenFGA check based on the target type (realm or device)
  defp check_openfga(user_id, relation, :realm, realm_name, _args) do
    OpenFGAClient.check("user:#{user_id}", relation, "realm:#{realm_name}")
  end

  defp check_openfga(user_id, relation, :device, _realm_name, args) do
    hw_id = Map.get(args, :hw_id)
    OpenFGAClient.check("user:#{user_id}", relation, "device:#{hw_id}")
  end
end
