defmodule Api.NotionClientTest do
  use ExUnit.Case, async: true
  alias Api.NotionClient

  test "append_fortune/3 returns mock success when NOTION_API_KEY is mock" do
    System.put_env("NOTION_API_KEY", "mock_notion_key")
    metadata = %{date: "2026-07-20", dasha: "Ketu - Venus", transit_moon: "Moon in 4th House", score: 85}
    assert {:ok, _} = NotionClient.append_fortune("Test Title", "Test Content", metadata)
  end
end
