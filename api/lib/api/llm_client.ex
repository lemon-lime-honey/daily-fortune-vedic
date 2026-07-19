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

    if is_nil(api_key) or api_key == "" or api_key == "mock_llm_key" do
      # Return a mock JSON reading if no valid key is provided (e.g. during testing)
      {:ok, """
      {
        "score": 85,
        "keyword": "행운이 가득한 날",
        "fortune": "오늘은 행운이 가득한 날입니다. 목성과 금성의 기운이 차트에 긍정적으로 작용하고 있습니다. 특히 재물운과 대인관계에서 좋은 흐름이 예상되니, 적극적으로 행동하는 것이 좋습니다."
      }
      """}
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

      case Req.post(url, json: body, params: [key: api_key]) do
        {:ok, %Req.Response{status: 200, body: %{"candidates" => [%{"content" => %{"parts" => [%{"text" => text}]}} | _]}}} ->
          {:ok, text}

        {:ok, %Req.Response{status: status, body: body}} ->
          {:error, {:http_error, status, body}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end
end
