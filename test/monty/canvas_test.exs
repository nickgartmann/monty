defmodule Monty.CanvasTest do
  use ExUnit.Case, async: true

  alias Monty.Canvas

  test "grid geometry and legacy rounding preserve origins to the nearest dot" do
    assert Canvas.grid_step() == 20
    assert Canvas.padding() == 32
    assert Canvas.card_width() == 240
    assert Canvas.card_height() == 188
    assert Canvas.max_x() == 200
    assert Canvas.max_y() == 1200

    for x <- 0..11, y <- 0..99 do
      {fine_x, fine_y} = Canvas.from_legacy_position(x, y)
      assert fine_x == x * 14
      assert abs(fine_y * Canvas.grid_step() - y * 224) <= 10

      assert Canvas.pixel_position(%{"x" => fine_x, "y" => fine_y}) ==
               {Canvas.padding() + x * 280, Canvas.padding() + fine_y * 20}
    end
  end

  test "size includes cards and padding without shrinking the initial canvas" do
    assert Canvas.size([]) == {904, 736}
    assert Canvas.size([%{"x" => 0, "y" => 0}]) == {904, 736}
    assert Canvas.size([%{"x" => 200, "y" => 1200}]) == {4304, 24_252}
  end

  test "free positions use the next non-overlapping default slot within the bounds" do
    assert Canvas.free_position([]) == {0, 0}
    assert Canvas.free_position([%{"x" => 0, "y" => 0}]) == {14, 0}

    assert Canvas.free_position([%{"x" => 0, "y" => 0}, %{"x" => 14, "y" => 0}]) ==
             {28, 0}

    assert Canvas.free_position(for x <- [0, 14, 28], do: %{"x" => x, "y" => 0}) ==
             {0, 11}

    assert Canvas.free_position([%{"x" => 3, "y" => 0}]) == {28, 0}

    metrics = for i <- 0..99, do: %{"x" => Enum.at([0, 14, 28], rem(i, 3)), "y" => div(i, 3) * 11}
    {x, y} = Canvas.free_position(metrics)
    assert x in 0..Canvas.max_x()
    assert y in 0..Canvas.max_y()
  end
end
