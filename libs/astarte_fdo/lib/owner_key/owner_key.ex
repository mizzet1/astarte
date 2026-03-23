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

defmodule Astarte.FDO.OwnerKey do
  @moduledoc """
  This module provides functions to manage owner keys,
  allowing to create and upload them in the OpenBao database.
  """

  alias Astarte.FDO.OwnerKeyOptions
  alias Astarte.Secrets
  alias Astarte.Secrets.Core

  def create_or_upload(
        %OwnerKeyOptions{
          action: "create",
          key_name: key_name,
          key_algorithm: key_algorithm
        },
        realm_name
      ) do
    {:ok, key_algorithm} = Core.string_to_key_type(key_algorithm)
    {:ok, namespace} = Secrets.create_namespace(realm_name, key_algorithm)

    # check if the key already exists and if so notify the user;
    # useful since OpenBao key creation is idempotent
    case Secrets.get_key(key_name, namespace: namespace) do
      {:ok, %{name: ^key_name}} ->
        {:ok, "The key #{key_name} has already been created"}

      _ ->
        do_create_key(key_name, key_algorithm, namespace)
    end
  end

  defp do_create_key(key_name, key_algorithm, namespace) do
    with {:ok, key_data} <-
           Secrets.create_keypair(key_name, key_algorithm, namespace: namespace) do
      public_key = get_in(key_data, ["keys", "1", "public_key"])
      {:ok, public_key}
    end
  end
end
