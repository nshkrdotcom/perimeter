defmodule PerimeterTest do
  use ExUnit.Case
  doctest Perimeter

  test "returns version" do
    assert Perimeter.version() == "0.0.1"
  end
end
