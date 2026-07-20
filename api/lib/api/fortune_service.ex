defmodule Api.FortuneService do
  @moduledoc """
  Core service that runs the daily fortune generation pipeline.
  """
  require Logger
  alias Api.{CalcClient, PromptBuilder, LlmClient, NotionClient}

  @doc """
  Executes the entire daily fortune pipeline from chart calculation to Notion upload.
  """
  def run_pipeline() do
    Logger.info("Starting daily fortune pipeline...")

    with {:ok, calc_data} <- get_chart_data_with_retry(),
         _ <- Logger.info("DEBUG: Raw Calc Data from Rust:\n#{inspect(calc_data, pretty: true)}"),
         prompt <- PromptBuilder.build_prompt(calc_data),
         _ <- Logger.info("DEBUG: Generated LLM Prompt:\n#{prompt}"),
         {:ok, raw_fortune_text} <- generate_fortune_with_retry(prompt),
         {:ok, parsed_json} <- parse_llm_response(raw_fortune_text),
         {:ok, _notion_response} <- upload_to_notion_with_retry(calc_data, parsed_json) do
      Logger.info("Daily fortune pipeline successfully completed.")
      :ok
    else
      {:error, reason} ->
        Logger.error("Daily fortune pipeline failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def get_chart_data_with_retry() do
    with_retry(fn ->
      birth_date = System.get_env("BIRTH_DATE") || "1995-01-01"
      birth_time = System.get_env("BIRTH_TIME") || "12:00:00"
      birth_lat = Float.parse(System.get_env("BIRTH_LAT") || "37.5665") |> elem(0)
      birth_lon = Float.parse(System.get_env("BIRTH_LON") || "126.9780") |> elem(0)
      birth_tz_offset = Float.parse(System.get_env("BIRTH_TZ_OFFSET") || "9.0") |> elem(0)
      target_tz_offset = Float.parse(System.get_env("TARGET_TZ_OFFSET") || "9.0") |> elem(0)

      [year, month, day] = String.split(birth_date, "-") |> Enum.map(&String.to_integer/1)
      [hour, minute, _] = String.split(birth_time, ":") |> Enum.map(&String.to_integer/1)

      local_now = DateTime.add(DateTime.utc_now(), trunc(target_tz_offset * 3600), :second)
      local_date = DateTime.to_date(local_now)

      params = %{
        "year" => year,
        "month" => month,
        "day" => day,
        "hour" => hour,
        "minute" => minute,
        "latitude" => birth_lat,
        "longitude" => birth_lon,
        "tz_offset" => birth_tz_offset,
        "target_year" => local_date.year,
        "target_month" => local_date.month,
        "target_day" => local_date.day,
        "target_tz_offset" => target_tz_offset
      }

      CalcClient.calculate_chart(params)
    end)
  end

  def generate_fortune_with_retry(prompt) do
    with_retry(fn -> LlmClient.generate_content(prompt) end)
  end

  def upload_to_notion_with_retry(calc_data, parsed_json) do
    with_retry(fn ->
      tz_offset = Float.parse(System.get_env("TARGET_TZ_OFFSET") || "9.0") |> elem(0)
      local_now = DateTime.add(DateTime.utc_now(), trunc(tz_offset * 3600), :second)
      local_date = DateTime.to_date(local_now)

      date_str =
        "#{local_date.year}-#{String.pad_leading(to_string(local_date.month), 2, "0")}-#{String.pad_leading(to_string(local_date.day), 2, "0")}"

      dasha_str = calc_data["current_dasha"] || "Unknown"
      transit_moon = calc_data["transit_moon_house"] || "Unknown"
      metrics = calc_data["daily_metrics"] || %{}

      title = parsed_json["keyword"] || "오늘의 운세"
      content = parsed_json["fortune"] || "운세 내용 없음"
      score = parsed_json["score"] || 50

      triggers_list = metrics["activated_triggers"] || []
      activated_triggers = Enum.map(triggers_list, & &1["name"]) |> Enum.uniq()

      metadata = %{
        date: date_str,
        dasha: dasha_str,
        transit_moon: transit_moon,
        score: score,
        tithi: metrics["tithi"] || "Unknown",
        nakshatra: metrics["nakshatra"] || "Unknown",
        yoga: metrics["yoga"] || "Unknown",
        karana: metrics["karana"] || "Unknown",
        weekday: metrics["weekday"] || "Unknown",
        tara_bala: metrics["tara_bala_category"] || "Unknown",
        transit_moon_sav: metrics["transit_moon_sav"] || 0,
        transit_moon_bav: metrics["transit_moon_bav"] || 0,
        activated_triggers: activated_triggers
      }

      NotionClient.append_fortune(title, content, metadata)
    end)
  end

  def parse_llm_response(raw_text) do
    cleaned =
      raw_text
      |> String.replace(~r/^```json\s*/, "")
      |> String.replace(~r/```\s*$/, "")
      |> String.trim()

    case Jason.decode(cleaned) do
      {:ok, parsed} ->
        {:ok, parsed}

      {:error, reason} ->
        Logger.error("Failed to parse LLM JSON response: #{inspect(reason)}. Raw text: #{raw_text}")
        {:ok, %{
          "score" => 50,
          "keyword" => "오늘의 운세",
          "fortune" => raw_text
        }}
    end
  end

  def with_retry(func, retries \\ 3, delay \\ 1000) do
    case func.() do
      {:ok, result} ->
        {:ok, result}

      {:error, reason} ->
        if retries > 0 do
          Logger.warning("Operation failed: #{inspect(reason)}. Retrying in #{delay}ms... (#{retries} attempts left)")
          :timer.sleep(delay)
          with_retry(func, retries - 1, delay * 2)
        else
          {:error, reason}
        end
    end
  end
end
