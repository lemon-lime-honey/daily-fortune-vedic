defmodule Api.CalcClient do
  @moduledoc """
  Client for interacting with the Rust-based `calc` service.
  """

  @doc """
  Sends natal details and target date to `calc` service to calculate charts and dasha.
  """
  def calculate_chart(params) do
    url = System.get_env("RUST_CALC_API_URL") || "http://localhost:8080"
    endpoint = "#{url}/calculate"

    case Req.post(endpoint, json: params, connect_options: [timeout: 5_000], receive_timeout: 30_000) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
