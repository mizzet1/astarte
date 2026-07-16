defmodule Astarte.PairingWeb.GraphQL.OpenFGAClient do
  @moduledoc """
  Thin HTTP client for the OpenFGA API: store discovery, relationship
  checks, tuple writes/deletes and ListObjects queries.
  """

  require Logger

  @default_url "http://localhost:8080"

  def base_url do
    Application.get_env(:astarte_pairing, :openfga_url) ||
      System.get_env("ASTARTE_PAIRING_OPENFGA_URL") || @default_url
  end

  @doc """
  Extracts a stable FGA user id from the Absinthe `current_user`. Only a
  non-nil `:id` field or `"sub"` claim is accepted; any other shape
  (including a `%User{id: nil}`) resolves to `nil` so callers reject the
  request instead of authorizing under a fabricated identity.
  """
  def resolve_user_id(nil), do: nil
  def resolve_user_id(%{id: id}) when not is_nil(id), do: id
  def resolve_user_id(%{"sub" => sub}) when not is_nil(sub), do: sub
  def resolve_user_id(_), do: nil

  @doc "Resolves the OpenFGA store id to use, or nil if OpenFGA isn't configured/reachable."
  def store_id do
    env_store_id = System.get_env("ASTARTE_PAIRING_OPENFGA_STORE_ID")

    if is_nil(env_store_id) or env_store_id == "" do
      case :persistent_term.get(:openfga_store_id, nil) do
        nil -> fetch_and_cache_store_id()
        cached_id -> cached_id
      end
    else
      env_store_id
    end
  end

  defp fetch_and_cache_store_id do
    url = base_url()
    Logger.info("==> [OpenFGA] Fetching store id dynamically from #{url}/stores")

    case HTTPoison.get("#{url}/stores") do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"stores" => [%{"id" => id} | _]}} ->
            Logger.info("==> [OpenFGA] Found and cached store id: #{id}")
            :persistent_term.put(:openfga_store_id, id)
            id

          _ ->
            Logger.warning("==> [OpenFGA] Could not find any stores")
            nil
        end

      {:error, error} ->
        Logger.warning("==> [OpenFGA] Failed to fetch stores: #{inspect(error)}")
        nil

      _ ->
        nil
    end
  end

  @doc "Checks whether `user` has `relation` on `object` (e.g. \"user:alice\", \"device_manager\", \"realm:test\")."
  @spec check(String.t(), String.t(), String.t()) ::
          :ok | {:error, :forbidden | :not_configured | term()}
  def check(user, relation, object) do
    store = store_id()

    if is_nil(store) or store == "" do
      {:error, :not_configured}
    else
      url = "#{base_url()}/stores/#{store}/check"

      body =
        Jason.encode!(%{
          "tuple_key" => %{"user" => user, "relation" => relation, "object" => object}
        })

      case HTTPoison.post(url, body, [{"Content-Type", "application/json"}]) do
        {:ok, %HTTPoison.Response{status_code: 200, body: resp_body}} ->
          case Jason.decode(resp_body) do
            {:ok, %{"allowed" => true}} -> :ok
            _ -> {:error, :forbidden}
          end

        {:ok, %HTTPoison.Response{status_code: status, body: resp_body}} ->
          Logger.warning("==> [OpenFGA] NON-200 STATUS on check: #{status} | BODY: #{resp_body}")
          {:error, :forbidden}

        {:error, %HTTPoison.Error{reason: reason}} ->
          {:error, reason}
      end
    end
  end

  @doc "Writes a single relationship tuple."
  @spec write_tuple(String.t(), String.t(), String.t()) :: :ok | {:error, term()}
  def write_tuple(user, relation, object), do: mutate_tuple("writes", user, relation, object)

  @doc "Deletes a single relationship tuple."
  @spec delete_tuple(String.t(), String.t(), String.t()) :: :ok | {:error, term()}
  def delete_tuple(user, relation, object), do: mutate_tuple("deletes", user, relation, object)

  defp mutate_tuple(op, user, relation, object) do
    store = store_id()

    if is_nil(store) or store == "" do
      {:error, :not_configured}
    else
      url = "#{base_url()}/stores/#{store}/write"

      body =
        Jason.encode!(%{
          op => %{
            "tuple_keys" => [%{"user" => user, "relation" => relation, "object" => object}]
          }
        })

      case HTTPoison.post(url, body, [{"Content-Type", "application/json"}]) do
        {:ok, %HTTPoison.Response{status_code: 200}} ->
          :ok

        {:ok, %HTTPoison.Response{status_code: status, body: resp_body}} ->
          Logger.warning("==> [OpenFGA] Tuple #{op} failed: #{status} | #{resp_body}")
          {:error, :request_failed}

        {:error, %HTTPoison.Error{reason: reason}} ->
          {:error, reason}
      end
    end
  end

  @doc "Lists the ids of objects of `type` that `user` has `relation` on, walking relationship composition."
  @spec list_objects(String.t(), String.t(), String.t()) :: {:ok, [String.t()]} | {:error, term()}
  def list_objects(user, relation, type) do
    store = store_id()

    if is_nil(store) or store == "" do
      {:error, :not_configured}
    else
      url = "#{base_url()}/stores/#{store}/list-objects"

      body =
        Jason.encode!(%{
          "type" => type,
          "relation" => relation,
          "user" => user
        })

      case HTTPoison.post(url, body, [{"Content-Type", "application/json"}]) do
        {:ok, %HTTPoison.Response{status_code: 200, body: resp_body}} ->
          case Jason.decode(resp_body) do
            {:ok, %{"objects" => objects}} -> {:ok, objects}
            _ -> {:error, :invalid_response}
          end

        {:ok, %HTTPoison.Response{status_code: status, body: resp_body}} ->
          Logger.warning("==> [OpenFGA] ListObjects failed: #{status} | #{resp_body}")
          {:error, :request_failed}

        {:error, %HTTPoison.Error{reason: reason}} ->
          {:error, reason}
      end
    end
  end
end
