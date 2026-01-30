defmodule ValidResultDebugTest do
  use ExUnit.Case, capture_log: false

  @moduletag :capture_log

  alias Astarte.Core.Interface

  import Astarte.Helpers.Device

  @tag :capture_io
  test "debug valid_result? with logs" do
    result = [%{"timestamp" => ~U[2026-01-29 11:18:01.957Z], "value" => ~U[1970-01-13 02:17:52.160Z]}]

    interface_to_update = %Interface{
      interface_id: <<182, 244, 159, 148, 116, 57, 75, 223, 140, 72, 130, 30, 196, 145, 69, 120>>,
      name: "rV.b",
      major_version: 6,
      minor_version: 50,
      type: :datastream,
      ownership: :server,
      aggregation: :individual,
      description: nil,
      doc: nil,
      mappings: [
        %Astarte.Core.Mapping{
          endpoint: "/q/individual_4358",
          value_type: :datetime,
          reliability: :unique,
          retention: :stored,

          explicit_timestamp: false,
          description: nil,
          doc: nil,
          endpoint_id: nil,
          interface_id: nil,
          path: nil,
          type: nil
        }
      ],
      quality: nil,
      aggregate: nil,
      interface_name: "rV.b",
      version_major: 6,
      version_minor: 50
    }

    expected_read_value = ~U[1970-01-13 02:17:52.160Z]

    IO.inspect(result, label: "result")
    IO.inspect(interface_to_update, label: "interface_to_update")
    IO.inspect(expected_read_value, label: "expected_read_value")

    res = Astarte.Helpers.Device.valid_result?(result, interface_to_update, expected_read_value)
    IO.inspect(res, label: "valid_result? returned")
    assert res
  end
end
