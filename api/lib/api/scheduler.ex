defmodule Api.Scheduler do
  @moduledoc """
  Task scheduler that runs the fortune pipeline daily at TARGET_HOUR:TARGET_MINUTE.
  """
  use GenServer
  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # Schedule the first run
    schedule_next_run()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:run_pipeline, state) do
    Logger.info("Starting scheduled daily fortune pipeline run...")

    case Api.FortuneService.run_pipeline() do
      :ok ->
        Logger.info("Scheduled pipeline run completed successfully.")

      {:error, reason} ->
        Logger.error("Scheduled pipeline run failed: #{inspect(reason)}")
    end

    schedule_next_run()
    {:noreply, state}
  end

  defp schedule_next_run() do
    # For testing/demo, we can configure a short interval (e.g. in seconds) via env.
    # Otherwise, calculate milliseconds until the next occurrence of TARGET_HOUR:TARGET_MINUTE.
    interval_sec = System.get_env("SCHEDULER_INTERVAL_SEC")

    ms_to_wait =
      if interval_sec && interval_sec != "" do
        String.to_integer(interval_sec) * 1000
      else
        calculate_ms_to_next_target()
      end

    Logger.info("Next pipeline run scheduled in #{ms_to_wait / 1000} seconds.")
    Process.send_after(self(), :run_pipeline, ms_to_wait)
  end

  def calculate_ms_to_next_target() do
    target_hour = String.to_integer(System.get_env("TARGET_HOUR") || "12")
    target_minute = String.to_integer(System.get_env("TARGET_MINUTE") || "0")
    tz_offset = Float.parse(System.get_env("TARGET_TZ_OFFSET") || "9.0") |> elem(0)

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
end
