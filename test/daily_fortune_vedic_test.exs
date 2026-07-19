defmodule DailyFortuneVedicTest do
  use ExUnit.Case
  doctest DailyFortuneVedic

  test "greets the world" do
    assert DailyFortuneVedic.hello() == :world
  end
end
