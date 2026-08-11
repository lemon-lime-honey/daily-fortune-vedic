defmodule Api.NotionClientTest do
  use ExUnit.Case, async: true
  alias Api.NotionClient

  test "append_fortune/3 returns error when NOTION_API_KEY is missing" do
    System.put_env("NOTION_API_KEY", "")
    metadata = %{
      date: "2026-07-20",
      dasha: "Ketu - Venus",
      transit_moon: "4",
      score: 85,
      tithi: "Shukla Pratipada",
      nakshatra: "Chitra",
      yoga: "Vishkambha",
      karana: "Bava",
      weekday: "Monday",
      tara_bala: "Sampat",
      transit_moon_sav: 29,
      transit_moon_bav: 5,
      activated_triggers: ["Mars", "Saturn"]
    }
    assert {:error, :missing_api_key} = NotionClient.append_fortune("Test Title", "Test Content", metadata)
  end
end
