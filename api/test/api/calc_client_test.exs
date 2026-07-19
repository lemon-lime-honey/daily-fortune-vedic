defmodule Api.CalcClientTest do
  use ExUnit.Case, async: true
  alias Api.CalcClient

  @valid_params %{
    "year" => 1995,
    "month" => 1,
    "day" => 1,
    "hour" => 12,
    "minute" => 0,
    "latitude" => 37.5665,
    "longitude" => 126.9780,
    "tz_offset" => 9.0,
    "target_year" => 2026,
    "target_month" => 7,
    "target_day" => 20
  }

  describe "calculate_chart/1" do
    test "returns {:ok, response} with valid params" do
      # Note: This test requires the `calc` server to be running.
      # If RUST_CALC_API_URL is set or defaults to localhost:8080.
      case CalcClient.calculate_chart(@valid_params) do
        {:ok, response} ->
          assert response["status"] == "success"
          assert is_map(response["natal_chart"])
          assert is_map(response["transit_chart"])
          assert is_map(response["dasha"])

        {:error, reason} ->
          flunk("Failed to call calc service: #{inspect(reason)}. Is the calc server running?")
      end
    end

    test "returns {:error, {:http_error, 400, _}} with invalid params" do
      invalid_params = Map.put(@valid_params, "month", 13)

      case CalcClient.calculate_chart(invalid_params) do
        {:error, {:http_error, 400, _body}} ->
          assert true

        other ->
          flunk("Expected HTTP 400 error, got: #{inspect(other)}")
      end
    end
  end
end
