defmodule Api.Scheduler do
  @moduledoc """
  Task scheduler that runs the fortune pipeline daily at TARGET_HOUR:TARGET_MINUTE.
  Includes short-interval retry for transient failures and startup catch-up sync.
  """
  use GenServer
  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    max_retries = Keyword.get(opts, :max_retries, parse_integer_env("SCHEDULER_MAX_RETRIES", 5))
    retry_delay_ms = Keyword.get(opts, :retry_delay_ms, parse_integer_env("SCHEDULER_RETRY_DELAY_MS", 300_000))
    enable_startup_check = Keyword.get(opts, :startup_check, System.get_env("DISABLE_STARTUP_CHECK") != "true")

    state = %{
      retry_count: 0,
      max_retries: max_retries,
      retry_delay_ms: retry_delay_ms
    }

    if enable_startup_check do
      Process.send_after(self(), :startup_check, 1000)
    else
      schedule_next_target_run()
    end

    {:ok, state}
  end

  @impl true
  def handle_info(:startup_check, state) do
    with {:ok, date_str, _} <- Api.FortuneService.resolve_target_date(nil) do
      case Api.Storage.get_record(date_str) do
        {:ok, %{"status" => "synced"}} ->
          Logger.info("Startup check: Fortune for #{date_str} is already synced. Scheduling next target run.")
          schedule_next_target_run()
          {:noreply, state}

        _ ->
          Logger.info("Startup check: Fortune for #{date_str} is not synced yet. Executing pipeline now.")
          send(self(), :run_pipeline)
          {:noreply, state}
      end
    else
      _ ->
        schedule_next_target_run()
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(:run_pipeline, state) do
    Logger.info("Starting scheduled daily fortune pipeline run...")

    case Api.FortuneService.run_pipeline() do
      :ok ->
        Logger.info("Scheduled pipeline run completed successfully.")
        schedule_next_target_run()
        {:noreply, %{state | retry_count: 0}}

      {:ok, :already_synced} ->
        Logger.info("Scheduled pipeline run skipped: already synced.")
        schedule_next_target_run()
        {:noreply, %{state | retry_count: 0}}

      {:error, reason} ->
        Logger.error("Scheduled pipeline run failed: #{inspect(reason)}")
        current_retries = state.retry_count
        max_retries = state.max_retries

        if current_retries < max_retries do
          delay = state.retry_delay_ms
          Logger.warning("Scheduling short retry #{current_retries + 1}/#{max_retries} in #{delay / 1000} seconds.")
          Process.send_after(self(), :run_pipeline, delay)
          {:noreply, %{state | retry_count: current_retries + 1}}
        else
          Logger.error("Max retries (#{max_retries}) exhausted. Scheduling next regular target run.")
          schedule_next_target_run()
          {:noreply, %{state | retry_count: 0}}
        end
    end
  end

  def schedule_next_target_run do
    ms_to_wait = calculate_ms_to_next_target()
    Logger.info("Next pipeline run scheduled in #{ms_to_wait / 1000} seconds.")
    Process.send_after(self(), :run_pipeline, ms_to_wait)
  end

  def calculate_ms_to_next_target do
    target_hour = parse_integer_env("TARGET_HOUR", 12)
    target_minute = parse_integer_env("TARGET_MINUTE", 0)
    tz_offset = parse_float_env("TARGET_TZ_OFFSET", 9.0)

    utc_now = DateTime.utc_now()
    local_now = DateTime.add(utc_now, trunc(tz_offset * 3600), :second)

    local_target_today =
      DateTime.new!(
        DateTime.to_date(local_now),
        Time.new!(target_hour, target_minute, 0),
        "Etc/UTC"
      )

    local_target =
      if DateTime.compare(local_now, local_target_today) == :lt do
        local_target_today
      else
        DateTime.add(local_target_today, 24 * 3600, :second)
      end

    diff_sec = DateTime.diff(local_target, local_now)
    diff_sec * 1000
  end

  defp parse_integer_env(key, default) do
    case System.get_env(key) do
      nil -> default
      "" -> default
      val ->
        case Integer.parse(val) do
          {int_val, _} -> int_val
          :error -> default
        end
    end
  end

  defp parse_float_env(key, default) do
    case System.get_env(key) do
      nil -> default
      "" -> default
      val ->
        case Float.parse(val) do
          {float_val, _} -> float_val
          :error -> default
        end
    end
  end
end
