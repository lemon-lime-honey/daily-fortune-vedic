defmodule Api.NotionClientTest do
  use ExUnit.Case, async: true
  alias Api.NotionClient

  test "append_fortune/2 returns mock success when NOTION_API_KEY is mock" do
    System.put_env("NOTION_API_KEY", "mock_notion_key")
    assert {:ok, _} = NotionClient.append_fortune("Test Title", "Test Content")
  end
end
