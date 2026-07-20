defmodule Api.LlmTest do
  use ExUnit.Case, async: true
  alias Api.PromptBuilder
  alias Api.LlmClient

  @dummy_calc_data %{
    "natal_chart" => %{
      "houses" => %{"asc" => 3.72},
      "planets" => [
        %{"name" => "Sun", "sign" => "Sagittarius", "house" => 9},
        %{"name" => "Moon", "sign" => "Sagittarius", "house" => 9}
      ]
    },
    "transit_chart" => %{
      "lagna_sign" => 1,
      "planets" => [
        %{"name" => "Sun", "sign" => "Cancer", "house" => 4},
        %{"name" => "Moon", "sign" => "Virgo", "house" => 6}
      ]
    },
    "dasha" => %{
      "moon_nakshatra" => "Moola",
      "maha_dashas" => [
        %{
          "lord" => "Ketu",
          "end_jd" => 2450004.1,
          "sub_periods" => [
            %{"lord" => "Ketu", "end_jd" => 2449735.2}
          ]
        }
      ]
    }
  }

  test "PromptBuilder.build_prompt/1 builds a prompt string" do
    prompt = PromptBuilder.build_prompt(@dummy_calc_data)
    assert String.contains?(prompt, "Ascendant (Lagna): Aries")
    assert String.contains?(prompt, "Birth Nakshatra: Moola")
    assert String.contains?(prompt, "Sun: Sagittarius (House 9)")
    assert String.contains?(prompt, "Sun: Cancer (House 4)")
    assert String.contains?(prompt, "Current Dasha Period:")
  end

  test "LlmClient.generate_content/1 returns mock result when API key is mock" do
    System.put_env("LLM_API_KEY", "mock_llm_key")
    {:ok, text} = LlmClient.generate_content("hello")
    assert String.contains?(text, "오늘")
  end
end
