defmodule Api.SchedulerTest do
  use ExUnit.Case, async: false
  alias Api.{Scheduler, Storage}

  @test_dir "data/test_scheduler_records"

  setup do
    System.put_env("DATA_DIR", @test_dir)
    File.rm_rf!(@test_dir)

    on_exit(fn ->
      File.rm_rf!(@test_dir)
      System.delete_env("DATA_DIR")
    end)

    :ok
  end

  test "calculate_ms_to_next_target/0 returns positive duration" do
    ms = Scheduler.calculate_ms_to_next_target()
    assert is_number(ms)
    assert ms > 0
    assert ms <= 24 * 3600 * 1000
  end

  test "handle_info :run_pipeline increments retry_count on error up to max_retries" do
    System.put_env("BIRTH_DATE", "invalid-date")

    state = %{
      retry_count: 0,
      max_retries: 3,
      retry_delay_ms: 100
    }

    assert {:noreply, state_1} = Scheduler.handle_info(:run_pipeline, state)
    assert state_1.retry_count == 1

    assert {:noreply, state_2} = Scheduler.handle_info(:run_pipeline, state_1)
    assert state_2.retry_count == 2

    assert {:noreply, state_3} = Scheduler.handle_info(:run_pipeline, state_2)
    assert state_3.retry_count == 3

    assert {:noreply, state_4} = Scheduler.handle_info(:run_pipeline, state_3)
    assert state_4.retry_count == 0
  end

  test "handle_info :startup_check detects already synced record and does not trigger run" do
    {:ok, date_str, _} = Api.FortuneService.resolve_target_date(nil)
    Storage.mark_synced(date_str, %{"page_id" => "p-123"})

    state = %{retry_count: 0, max_retries: 3, retry_delay_ms: 100}
    assert {:noreply, ^state} = Scheduler.handle_info(:startup_check, state)
  end
end
