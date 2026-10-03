defmodule Monty.CanvasTest do
  use ExUnit.Case, async: true

  alias Monty.Canvas

  test "grid geometry and legacy rounding preserve origins to the nearest dot" do
    assert Canvas.grid_step() == 20
    assert Canvas.padding() == 32
    assert Canvas.card_width() == 240
    assert Canvas.card_height() == 120

    for x <- 0..11, y <- 0..99 do
      {fine_x, fine_y} = Canvas.from_legacy_position(x, y)
      assert fine_x == x * 14
      assert abs(fine_y * Canvas.grid_step() - y * 224) <= 10

      assert Canvas.pixel_position(%{"x" => fine_x, "y" => fine_y}) ==
               {Canvas.padding() + x * 280, Canvas.padding() + fine_y * 20}
    end
  end

  test "new preset spacing fits compact cards without reinterpreting legacy positions" do
    assert Canvas.default_position(1, 1) == {14, 8}
    assert Canvas.from_legacy_position(1, 1) == {14, 11}
    {_, row} = Canvas.default_position(0, 1)
    assert row * Canvas.grid_step() == Canvas.card_height() + 40
  end

  test "pixel positions use the same grid for signed coordinates" do
    assert Canvas.pixel_position(%{"x" => -3, "y" => -4}) == {-28, -48}
  end

  test "free positions use the next non-overlapping default slot in row-major order" do
    assert Canvas.free_position([]) == {0, 0}
    assert Canvas.free_position([%{"x" => 0, "y" => 0}]) == {14, 0}

    assert Canvas.free_position([%{"x" => 0, "y" => 0}, %{"x" => 14, "y" => 0}]) ==
             {28, 0}

    assert Canvas.free_position(for x <- [0, 14, 28], do: %{"x" => x, "y" => 0}) ==
             {0, 8}

    assert Canvas.free_position([%{"x" => 3, "y" => 0}]) == {28, 0}

    metrics = for i <- 0..99, do: %{"x" => Enum.at([0, 14, 28], rem(i, 3)), "y" => div(i, 3) * 8}
    assert Canvas.free_position(metrics) == {14, 264}

    occupied = for row <- 0..150, x <- [0, 14, 28], do: %{"x" => x, "y" => row * 8}
    assert Canvas.free_position(occupied) == {0, 1208}
  end
end
