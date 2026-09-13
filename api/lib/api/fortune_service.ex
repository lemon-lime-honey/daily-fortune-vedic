defmodule Api.FortuneService do
  @moduledoc """
  Core service that runs the daily fortune generation pipeline.
  """
  require Logger
  alias Api.{CalcClient, PromptBuilder, LlmClient, NotionClient, Storage}

  @doc """
  Executes the daily fortune pipeline with local staging and idempotent step resumption.
  Accepts an optional target_date (YYYY-MM-DD string or Date struct).
  """
  def run_pipeline(target_date \\ nil) do
    with {:ok, date_str, local_date} <- resolve_target_date(target_date) do
      Logger.info("Starting daily fortune pipeline for #{date_str}...")

      case Storage.get_record(date_str) do
        {:ok, %{"status" => "synced"}} ->
          Logger.info("Daily fortune for #{date_str} is already synced. Skipping.")
          {:ok, :already_synced}

        existing_res ->
          existing_record =
            case existing_res do
              {:ok, rec} -> rec
              _ -> %{}
            end

          with {:ok, calc_data} <- ensure_calc_data(date_str, local_date, existing_record),
               {:ok, parsed_json} <- ensure_llm_result(date_str, calc_data, existing_record),
               {:ok, _notion_res} <- sync_to_notion(date_str, calc_data, parsed_json) do
            Logger.info("Daily fortune pipeline successfully completed and synced for #{date_str}.")
            :ok
          else
            {:error, reason} ->
              Logger.error("Daily fortune pipeline failed for #{date_str}: #{inspect(reason)}")
              {:error, reason}
          end
      end
    end
  end

  def resolve_target_date(nil) do
    with {:ok, target_tz_offset} <- parse_float_env("TARGET_TZ_OFFSET", 9.0) do
      local_now = DateTime.add(DateTime.utc_now(), trunc(target_tz_offset * 3600), :second)
      local_date = DateTime.to_date(local_now)
      {:ok, Date.to_iso8601(local_date), local_date}
    end
  end

  def resolve_target_date(%Date{} = local_date) do
    {:ok, Date.to_iso8601(local_date), local_date}
  end

  def resolve_target_date(date_str) when is_binary(date_str) do
    case Date.from_iso8601(date_str) do
      {:ok, local_date} -> {:ok, date_str, local_date}
      {:error, reason} -> {:error, {:invalid_target_date, reason}}
    end
  end

  defp ensure_calc_data(date_str, local_date, existing_record) do
    case Map.get(existing_record, "calc_data") do
      calc_data when is_map(calc_data) and map_size(calc_data) > 0 ->
        Logger.info("Found existing calculation data for #{date_str} in local storage. Skipping calc API call.")
        {:ok, calc_data}

      _ ->
        with {:ok, calc_data} <- get_chart_data_with_retry(local_date) do
          Logger.info("DEBUG: Raw Calc Data from Rust:\n#{inspect(calc_data, pretty: true)}")
          Storage.save_calc_data(date_str, calc_data)
          {:ok, calc_data}
        end
    end
  end

  defp ensure_llm_result(date_str, calc_data, existing_record) do
    case Map.get(existing_record, "llm_result") do
      llm_result when is_map(llm_result) and map_size(llm_result) > 0 ->
        Logger.info("Found existing LLM fortune result for #{date_str} in local storage. Skipping LLM generation.")
        {:ok, llm_result}

      _ ->
        prompt = PromptBuilder.build_prompt(calc_data)
        Logger.info("DEBUG: Generated LLM Prompt:\n#{prompt}")

        with {:ok, raw_fortune_text} <- generate_fortune_with_retry(prompt),
             {:ok, parsed_json} <- parse_llm_response(raw_fortune_text) do
          Storage.save_llm_result(date_str, parsed_json)
          {:ok, parsed_json}
        end
    end
  end

  defp sync_to_notion(date_str, calc_data, parsed_json) do
    with {:ok, notion_res} <- upload_to_notion_with_retry(date_str, calc_data, parsed_json) do
      page_id = (is_map(notion_res) && Map.get(notion_res, "id")) || "unknown"
      now_iso = DateTime.utc_now() |> DateTime.to_iso8601()
      Storage.mark_synced(date_str, %{"page_id" => page_id, "synced_at" => now_iso})
      {:ok, notion_res}
    end
  end

  def get_chart_data_with_retry(local_date \\ nil) do
    with_retry(fn ->
      with {:ok, birth_lat} <- parse_float_env("BIRTH_LAT", 37.5665),
           {:ok, birth_lon} <- parse_float_env("BIRTH_LON", 126.9780),
           {:ok, birth_tz_offset} <- parse_float_env("BIRTH_TZ_OFFSET", 9.0),
           {:ok, target_tz_offset} <- parse_float_env("TARGET_TZ_OFFSET", 9.0),
           {:ok, year, month, day} <- parse_date_env("BIRTH_DATE", "1995-01-01"),
           {:ok, hour, minute} <- parse_time_env("BIRTH_TIME", "12:00:00") do
        date =
          case local_date do
            %Date{} = d -> d
            _ ->
              local_now = DateTime.add(DateTime.utc_now(), trunc(target_tz_offset * 3600), :second)
              DateTime.to_date(local_now)
          end

        params = %{
          "year" => year,
          "month" => month,
          "day" => day,
          "hour" => hour,
          "minute" => minute,
          "latitude" => birth_lat,
          "longitude" => birth_lon,
          "tz_offset" => birth_tz_offset,
          "target_year" => date.year,
          "target_month" => date.month,
          "target_day" => date.day,
          "target_tz_offset" => target_tz_offset
        }

        CalcClient.calculate_chart(params)
      end
    end)
  end

  def generate_fortune_with_retry(prompt) do
    with_retry(fn -> LlmClient.generate_content(prompt) end)
  end

  def upload_to_notion_with_retry(date_str, calc_data, parsed_json) do
    with_retry(fn ->
      dasha_str = calc_data["current_dasha"] || "Unknown"
      transit_moon = calc_data["transit_moon_house"] || "Unknown"
      metrics = calc_data["daily_metrics"] || %{}

      title = parsed_json["keyword"] || "오늘의 운세"
      content = parsed_json["fortune"] || "운세 내용 없음"
      score = parsed_json["score"] || 50

      triggers_list = metrics["activated_triggers"] || []
      activated_triggers = Enum.map(triggers_list, &(&1["name"] || "Unknown")) |> Enum.uniq()

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
        {:error, :llm_parsing_failed}
    end
  end

  def with_retry(func, retries \\ 3, delay \\ 3000) do
    case func.() do
      {:ok, result} ->
        {:ok, result}

      {:error, reason} ->
        if should_retry?(reason) and retries > 0 do
          Logger.warning("Transient error: #{inspect(reason)}. Retrying in #{delay}ms... (#{retries} attempts left)")
          :timer.sleep(delay)
          with_retry(func, retries - 1, delay * 2)
        else
          Logger.error("Operation failed deterministically or retries exhausted: #{inspect(reason)}")
          {:error, reason}
        end
    end
  end

  defp should_retry?({:http_error, status, _}) when status in [408, 429, 500, 502, 503, 504], do: true
  defp should_retry?({:http_error, _status, _}), do: false
  defp should_retry?(:timeout), do: true
  defp should_retry?(:econnrefused), do: true
  defp should_retry?(%Req.TransportError{}), do: true
  defp should_retry?(_), do: false

  defp parse_float_env(key, default) do
    case System.get_env(key) do
      nil -> {:ok, default}
      "" -> {:ok, default}
      val ->
        case Float.parse(val) do
          {float_val, _} -> {:ok, float_val}
          :error -> {:error, {:invalid_env_format, key, val}}
        end
    end
  end

  defp parse_date_env(key, default) do
    val = System.get_env(key) || default
    val = if val == "", do: default, else: val
    case String.split(val, "-") do
      [y, m, d] ->
        try do
          {:ok, String.to_integer(y), String.to_integer(m), String.to_integer(d)}
        rescue
          ArgumentError -> {:error, {:invalid_env_format, key, val}}
        end
      _ -> {:error, {:invalid_env_format, key, val}}
    end
  end

  defp parse_time_env(key, default) do
    val = System.get_env(key) || default
    val = if val == "", do: default, else: val
    parts = String.split(val, ":")
    if length(parts) >= 2 do
      try do
        {:ok, String.to_integer(Enum.at(parts, 0)), String.to_integer(Enum.at(parts, 1))}
      rescue
        ArgumentError -> {:error, {:invalid_env_format, key, val}}
      end
    else
      {:error, {:invalid_env_format, key, val}}
    end
  end
end
