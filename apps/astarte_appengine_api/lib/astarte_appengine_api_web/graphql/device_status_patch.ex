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

defmodule Astarte.AppEngine.APIWeb.GraphQL.DeviceStatusPatch do
  @moduledoc """
  Translates the input of the `updateDeviceStatus` mutation into the JSON Merge
  Patch of the REST API, the one `Astarte.AppEngine.API.Device.merge_device_status/3`
  takes.

  Aliases and attributes arrive as lists of `{key, value}` entries, where a null
  value removes the key. A key can't be listed twice and its value can't be
  omitted, since a merge patch always has one value per key.
  """

  @type entry :: %{required(:key) => String.t(), optional(:value) => String.t() | nil}

  @spec from_input(map()) :: {:ok, map()} | {:error, :invalid_alias | :invalid_attributes}
  def from_input(input) do
    with {:ok, aliases} <- to_map(input[:aliases], :invalid_alias),
         {:ok, attributes} <- to_map(input[:attributes], :invalid_attributes) do
      patch = %{"aliases" => aliases, "attributes" => attributes}

      {:ok, put_credentials_inhibited(patch, input)}
    end
  end

  # nil leaves the map unchanged, as a null does in the merge patch
  defp to_map(nil, _error), do: {:ok, nil}

  defp to_map(entries, error) do
    Enum.reduce_while(entries, {:ok, %{}}, fn
      %{key: key, value: value}, {:ok, map} when not is_map_key(map, key) ->
        {:cont, {:ok, Map.put(map, key, value)}}

      _entry, _acc ->
        {:halt, {:error, error}}
    end)
  end

  # a null credentials_inhibited clears it, so it is kept only when the input has it
  defp put_credentials_inhibited(patch, %{credentials_inhibited: credentials_inhibited}),
    do: Map.put(patch, "credentials_inhibited", credentials_inhibited)

  defp put_credentials_inhibited(patch, _input), do: patch
end
