defmodule Api.PromptBuilder do
  @moduledoc """
  Constructs prompts for LLM fortune generation based on computed chart data and daily Jyotish metrics.
  """

  @signs [
    "Aries", "Taurus", "Gemini", "Cancer", "Leo", "Virgo",
    "Libra", "Scorpio", "Sagittarius", "Capricorn", "Aquarius", "Pisces"
  ]

  @doc """
  Builds the prompt string using natal, transit, dasha, and daily metrics.
  """
  def build_prompt(calc_data) do
    natal_chart = calc_data["natal_chart"]
    transit_chart = calc_data["transit_chart"]
    dasha = calc_data["dasha"]
    metrics = calc_data["daily_metrics"] || %{}

    lagna_sign = transit_chart["lagna_sign"] || 3 # Default to Gemini (3) if not found
    asc_sign = Enum.at(@signs, lagna_sign - 1)

    natal_planets_str =
      natal_chart["planets"]
      |> Enum.map(fn p ->
        retro = if p["retrograde"] == true, do: " (Retrograde)", else: ""
        "- #{p["name"]}: #{p["sign"]} (House #{p["house"]})#{retro}"
      end)
      |> Enum.join("\n")

    current_dasha_str = calc_data["current_dasha"] || "Unknown"

    triggers = metrics["activated_triggers"] || []
    active_planet_names =
      triggers
      |> Enum.map(fn t -> t["name"] end)
      |> MapSet.new()

    active_triggers_str =
      if Enum.empty?(triggers) do
        "- None (No active planetary aspects or Gochara Vedha obstructions today)"
      else
        triggers
        |> Enum.map(fn t ->
          "- Transit #{t["name"]}: #{t["relationship"]} (Transit House #{t["transit_house_from_lagna"]})"
        end)
        |> Enum.join("\n")
      end

    passive_planets_str =
      transit_chart["planets"]
      |> Enum.filter(fn p -> not MapSet.member?(active_planet_names, p["name"]) end)
      |> Enum.map(fn p ->
        retro = if p["retrograde"] == true, do: " (Retrograde)", else: ""
        "- Transit #{p["name"]}: #{p["sign"]} (House #{p["house"]})#{retro} (Passive background, no direct aspect today)"
      end)
      |> Enum.join("\n")

    """
    You are a professional Vedic Astrologer (Jyotishi). Generate a highly precise, insightful, and practical daily fortune reading in Korean (한국어) based strictly on the provided birth, transit, and panchanga details.

    # Birth details (Natal Kundali)
    - Ascendant (Lagna): #{asc_sign}
    - Birth Nakshatra: #{dasha["moon_nakshatra"]}
    - Planet Positions:
    #{natal_planets_str}

    ### Daily Astrological Triggers (오늘 활성화된 행성적 트리거)
    * Note: These transiting planets are currently aspecting or conjoining your static natal planets today, or under Gochara Vedha obstructions. Focus heavily on these active triggers for today's horoscope.
    #{active_triggers_str}

    ### Passive Background Environment (배경에 머무는 행성 기류)
    * Note: These transiting planets have no active aspects with your natal planets today. Do NOT make them the main theme of today's fortune.
    #{passive_planets_str}

    ### Current Vimshottari Dasha
    - Current Dasha Period: #{current_dasha_str}
    * Note: Dasha Lord acts as the active energy switch. Focus on its transit position to see which daily aspects are actively felt.

    ### Panchanga & Daily Energy Metrics
    - Weekday (Vara): #{metrics["weekday"]} (Ruler: #{metrics["weekday_ruler"]})
    - Tithi: #{metrics["tithi"]}
    - Nakshatra: #{metrics["nakshatra"]}
    - Yoga: #{metrics["yoga"]}
    - Tara Bala: #{metrics["tara_bala_category"]} (#{metrics["tara_bala_description"]})
    - Transit Moon SAV: #{metrics["transit_moon_sav"]} (Supportive)
    - Transit Moon BAV: #{metrics["transit_moon_bav"]} (Stable)

    ### Crucial Astrological Analysis Instructions
    1. **Strict Data Compliance**: You MUST ONLY use the house numbers and signs provided in the lists above. Do not fabricate, move, or ignore any placements.
    2. **Vedic Astrology (Jyotish) Rules Only**: Do not use Western astrology concepts, Placidus systems, or minor aspects. Only apply Whole Sign transits and Vedic Drishti (especially Special Drishti of Mars: 4/7/8, Jupiter: 5/7/9, Saturn: 3/7/10).
    3. **Panchanga & Weekday Synthesis**: Ground the day's macro atmosphere by combining the Weekday ruler, Tithi, and Nakshatra.
    4. **Strict Trigger Limitation**: 
       - Do not treat planets in the 'Passive Background Environment' as the primary source of today's events or warnings. You MUST only use the 'Daily Astrological Triggers' list to describe the specific events, psychological shifts, or cautionary advice for today.
       - If a planet has Gochara Vedha (obstruction), describe its promised positive results as temporarily delayed, blocked, or challenged by external obstacles.
    5. **Quantitative Binding**: Deduce the daily fortune strictly from the Tara Bala and Ashtakavarga scores (SAV/BAV) provided in the metrics. Explain *why* these scores lead to your conclusions instead of just listing the numbers.
    6. **Output Constraints**: 
       - Write entirely in Korean. Do not use exclamation marks (!) in the Korean response.
       - Use arabic numbers (e.g. 3) instead of Korean words (e.g. 셋) when expressing numeric values.
       - Return a raw JSON object containing exactly three keys: "score", "keyword", and "fortune".
    """
  end
end
