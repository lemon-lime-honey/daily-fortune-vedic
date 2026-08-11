defmodule Api.LlmClient do
  @moduledoc """
  Client for interacting with the Google Gemini API.
  """

  @doc """
  Sends a prompt to Gemini and returns the generated text.
  """
  def generate_content(prompt) do
    api_key = System.get_env("LLM_API_KEY")
    model = System.get_env("LLM_MODEL_NAME") || "gemini-1.5-flash"

    if is_nil(api_key) or api_key == "" do
      {:error, :missing_api_key}
    else
      url = "https://generativelanguage.googleapis.com/v1beta/models/#{model}:generateContent"

      body = %{
        "contents" => [
          %{
            "parts" => [
              %{"text" => prompt}
            ]
          }
        ]
      }

      case Req.post(url, json: body, params: [key: api_key], receive_timeout: 90_000) do
        {:ok, %Req.Response{status: 200, body: %{"candidates" => [%{"content" => %{"parts" => parts}} | _]}}} ->
          text =
            parts
            |> Enum.reject(fn p -> Map.get(p, "thought") == true end)
            |> Enum.map(fn p -> Map.get(p, "text") || "" end)
            |> Enum.join("")

          {:ok, text}

        {:ok, %Req.Response{status: status, body: body}} ->
          {:error, {:http_error, status, body}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end
end
