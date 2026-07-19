defmodule Api.FortuneServiceTest do
  use ExUnit.Case, async: false
  alias Api.FortuneService

  test "run_pipeline/0 executes successfully" do
    # Set up required env vars
    System.put_env("BIRTH_DATE", "1995-01-01")
    System.put_env("BIRTH_TIME", "12:00:00")
    System.put_env("BIRTH_LAT", "37.5665")
    System.put_env("BIRTH_LON", "126.9780")
    System.put_env("TARGET_TZ_OFFSET", "9.0")
    System.put_env("LLM_API_KEY", "mock_llm_key")
    System.put_env("NOTION_API_KEY", "mock_notion_key")

    assert FortuneService.run_pipeline() == :ok
  end
end
