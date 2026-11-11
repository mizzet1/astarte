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

defmodule Astarte.AppEngine.APIWeb.GraphQL.DeviceStatusPatchTest do
  use ExUnit.Case, async: true

  alias Astarte.AppEngine.APIWeb.GraphQL.DeviceStatusPatch

  test "turns the entries into maps, with a null value removing the key" do
    input = %{
      aliases: [%{key: "name", value: "press"}, %{key: "serial", value: nil}],
      attributes: [%{key: "plant", value: ""}]
    }

    assert {:ok, patch} = DeviceStatusPatch.from_input(input)
    assert patch["aliases"] == %{"name" => "press", "serial" => nil}
    assert patch["attributes"] == %{"plant" => ""}
  end

  test "an omitted or null list leaves the map unchanged" do
    assert {:ok, %{"aliases" => nil, "attributes" => nil}} =
             DeviceStatusPatch.from_input(%{aliases: nil})
  end

  test "keeps credentials_inhibited only when the input has it" do
    assert {:ok, %{"credentials_inhibited" => true}} =
             DeviceStatusPatch.from_input(%{credentials_inhibited: true})

    assert {:ok, %{"credentials_inhibited" => nil}} =
             DeviceStatusPatch.from_input(%{credentials_inhibited: nil})

    assert {:ok, patch} = DeviceStatusPatch.from_input(%{})
    refute Map.has_key?(patch, "credentials_inhibited")
  end

  test "rejects a key listed twice" do
    entries = [%{key: "name", value: "press"}, %{key: "name", value: nil}]

    assert {:error, :invalid_alias} = DeviceStatusPatch.from_input(%{aliases: entries})
    assert {:error, :invalid_attributes} = DeviceStatusPatch.from_input(%{attributes: entries})
  end

  test "rejects an entry without a value" do
    entries = [%{key: "name"}]

    assert {:error, :invalid_alias} = DeviceStatusPatch.from_input(%{aliases: entries})
    assert {:error, :invalid_attributes} = DeviceStatusPatch.from_input(%{attributes: entries})
  end
end
