defmodule Api.FortuneServiceTest do
  use ExUnit.Case, async: false
  alias Api.FortuneService

  test "run_pipeline/0 handles errors gracefully instead of crashing" do
    System.put_env("BIRTH_DATE", "1995-01-01")
    System.put_env("BIRTH_TIME", "12:00:00")
    System.put_env("BIRTH_LAT", "37.5665")
    System.put_env("BIRTH_LON", "126.9780")
    System.put_env("TARGET_TZ_OFFSET", "9.0")
    System.put_env("LLM_API_KEY", "")
    System.put_env("NOTION_API_KEY", "")

    result = FortuneService.run_pipeline()
    assert match?({:error, _}, result)
  end
end
