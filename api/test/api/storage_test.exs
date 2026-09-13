defmodule Api.StorageTest do
  use ExUnit.Case, async: false
  alias Api.Storage

  @test_dir "data/test_records"

  setup do
    System.put_env("DATA_DIR", @test_dir)
    File.rm_rf!(@test_dir)

    on_exit(fn ->
      File.rm_rf!(@test_dir)
      System.delete_env("DATA_DIR")
    end)

    :ok
  end

  test "get_record/1 returns {:error, :not_found} for non-existent record" do
    assert Storage.get_record("2026-09-13") == {:error, :not_found}
  end

  test "save_calc_data/2 creates new record with calculated status" do
    calc_data = %{"current_dasha" => "Jupiter - Ketu", "test" => 123}
    assert {:ok, record} = Storage.save_calc_data("2026-09-13", calc_data)

    assert record["date"] == "2026-09-13"
    assert record["status"] == "calculated"
    assert record["calc_data"] == calc_data
    assert record["llm_result"] == nil

    assert {:ok, loaded} = Storage.get_record("2026-09-13")
    assert loaded["status"] == "calculated"
    assert loaded["calc_data"] == calc_data
  end

  test "save_llm_result/2 updates record with generated status" do
    calc_data = %{"current_dasha" => "Jupiter - Ketu"}
    Storage.save_calc_data("2026-09-13", calc_data)

    llm_result = %{"score" => 85, "keyword" => "협력", "fortune" => "좋은 날입니다."}
    assert {:ok, record} = Storage.save_llm_result("2026-09-13", llm_result)

    assert record["status"] == "generated"
    assert record["calc_data"] == calc_data
    assert record["llm_result"] == llm_result

    assert {:ok, loaded} = Storage.get_record("2026-09-13")
    assert loaded["status"] == "generated"
    assert loaded["llm_result"]["score"] == 85
  end

  test "mark_synced/2 updates record with synced status and notion meta" do
    calc_data = %{"current_dasha" => "Jupiter - Ketu"}
    Storage.save_calc_data("2026-09-13", calc_data)
    llm_result = %{"score" => 85, "keyword" => "협력", "fortune" => "좋은 날입니다."}
    Storage.save_llm_result("2026-09-13", llm_result)

    notion_meta = %{"page_id" => "page-123", "synced_at" => "2026-09-13T10:00:00Z"}
    assert {:ok, record} = Storage.mark_synced("2026-09-13", notion_meta)

    assert record["status"] == "synced"
    assert record["notion"] == notion_meta

    assert {:ok, loaded} = Storage.get_record("2026-09-13")
    assert loaded["status"] == "synced"
  end

  test "list_records/0 and get_pending_records/0 return correct subsets" do
    Storage.save_calc_data("2026-09-11", %{"day" => 11})
    Storage.mark_synced("2026-09-11", %{"page_id" => "11"})

    Storage.save_calc_data("2026-09-12", %{"day" => 12})
    Storage.save_llm_result("2026-09-12", %{"score" => 70})

    Storage.save_calc_data("2026-09-13", %{"day" => 13})

    assert {:ok, all} = Storage.list_records()
    assert length(all) == 3
    dates = Enum.map(all, & &1["date"])
    assert dates == ["2026-09-13", "2026-09-12", "2026-09-11"]

    assert {:ok, pending} = Storage.get_pending_records()
    assert length(pending) == 2
    pending_dates = Enum.map(pending, & &1["date"])
    assert pending_dates == ["2026-09-13", "2026-09-12"]
  end
end
