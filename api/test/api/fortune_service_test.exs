defmodule Api.FortuneServiceTest do
  use ExUnit.Case, async: false
  alias Api.{FortuneService, Storage}

  @test_dir "data/test_fortune_records"

  setup do
    System.put_env("DATA_DIR", @test_dir)
    File.rm_rf!(@test_dir)

    on_exit(fn ->
      File.rm_rf!(@test_dir)
      System.delete_env("DATA_DIR")
    end)

    :ok
  end

  test "run_pipeline/0 handles errors gracefully instead of crashing" do
    System.put_env("BIRTH_DATE", "invalid-date")
    result = FortuneService.run_pipeline("2026-09-13")
    assert match?({:error, _}, result)
  end

  test "run_pipeline/1 returns {:ok, :already_synced} if record is already synced" do
    Storage.mark_synced("2026-09-13", %{"page_id" => "p-123"})
    assert FortuneService.run_pipeline("2026-09-13") == {:ok, :already_synced}
  end

  test "run_pipeline/1 reuses existing calc_data and fails at LLM when missing api key" do
    calc_data = %{
      "current_dasha" => "Jupiter - Ketu",
      "natal_chart" => %{"planets" => []},
      "transit_chart" => %{},
      "daily_metrics" => %{},
      "transit_moon_house" => 4
    }
    Storage.save_calc_data("2026-09-13", calc_data)
    System.put_env("LLM_API_KEY", "")

    # Should not attempt to call calc service because calc_data exists, but will fail at LLM
    result = FortuneService.run_pipeline("2026-09-13")
    assert match?({:error, _}, result)

    # Verify calc_data was preserved in storage
    assert {:ok, record} = Storage.get_record("2026-09-13")
    assert record["calc_data"] == calc_data
  end
end

