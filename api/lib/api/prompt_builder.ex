defmodule Api.PromptBuilder do
  @moduledoc """
  Constructs prompts for LLM fortune generation based on computed chart data.
  """

  @signs [
    "Aries", "Taurus", "Gemini", "Cancer", "Leo", "Virgo",
    "Libra", "Scorpio", "Sagittarius", "Capricorn", "Aquarius", "Pisces"
  ]

  @doc """
  Builds the prompt string using natal, transit, and dasha data.
  """
  def build_prompt(calc_data) do
    natal_chart = calc_data["natal_chart"]
    transit_chart = calc_data["transit_chart"]
    dasha = calc_data["dasha"]

    asc_deg = natal_chart["houses"]["asc"]
    asc_sign = Enum.at(@signs, trunc(asc_deg / 30.0))

    natal_planets_str =
      natal_chart["planets"]
      |> Enum.map(fn p -> "- #{p["name"]}: #{p["sign"]} (House #{p["house"]})" end)
      |> Enum.join("\n")

    transit_planets_str =
      transit_chart["planets"]
      |> Enum.map(fn p -> "- #{p["name"]}: #{p["sign"]} (House #{p["house"]})" end)
      |> Enum.join("\n")

    current_dasha_str = format_current_dasha(dasha)

    """
    You are a professional Vedic Astrologer. Generate a daily fortune reading in Korean (한국어) based on the following birth and transit details.

    # Birth details
    - Ascendant (Lagna): #{asc_sign}
    - Birth Nakshatra: #{dasha["moon_nakshatra"]}
    - Planet Positions:
    #{natal_planets_str}

    ### Current Transits (Gochar)
    - Planet Positions:
    #{transit_planets_str}

    ### Current Vimshottari Dasha
    #{current_dasha_str}

    ### Instructions
    1. Analyze the interaction between the Natal Chart and the current Transit (Gochar) positions, especially relating to the current Vimshottari Dasha lord.
    2. Provide a detailed, insightful, and practical daily fortune reading.
    3. The tone must be professional, reassuring, yet realistic.
    4. Write the output entirely in Korean.
    5. Never use exclamation marks (!) in the Korean response.
    6. Use arabic numbers (e.g. 3) instead of Korean number words (e.g. 셋) when expressing numeric values.
    7. You MUST return the output as a raw JSON object containing exactly three keys:
       - "score": An integer between 0 and 100 representing the daily fortune score.
       - "keyword": A short string (1 sentence, max 10 words) summarizing the core theme of today's fortune (e.g., "정서적 안정이 필요한 날").
       - "fortune": The detailed daily fortune reading (3-4 paragraphs, no headers, no markdown, natural flowing text in Korean).
    """
  end

  defp format_current_dasha(dasha) do
    dasha["maha_dashas"]
    |> Enum.map(fn md ->
      subs =
        md["sub_periods"]
        |> Enum.map(fn sd -> "  - #{sd["lord"]} (ends at JD #{sd["end_jd"]})" end)
        |> Enum.join("\n")

      "- #{md["lord"]} (ends at JD #{md["end_jd"]}):\n#{subs}"
    end)
    |> Enum.join("\n")
  end
end
