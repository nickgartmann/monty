defmodule Monty.Canvas do
  @moduledoc """
  Shared geometry for metric positions. Coordinates are integer indices on a
  20px grid, measured from the canvas's 32px padding.
  """

  @grid_step 20
  @padding 32
  @card_width 240
  @card_height 188
  @max_x 200
  @max_y 1200
  @minimum_width 904
  @minimum_height 736
  @legacy_column_step 280
  @legacy_row_step 224

  def grid_step, do: @grid_step
  def padding, do: @padding
  def card_width, do: @card_width
  def card_height, do: @card_height
  def max_x, do: @max_x
  def max_y, do: @max_y

  @doc "Converts a version 1 grid origin to the closest fine-grid origin."
  def from_legacy_position(x, y) when is_integer(x) and is_integer(y) do
    {div(x * @legacy_column_step, @grid_step),
     div(y * @legacy_row_step + div(@grid_step, 2), @grid_step)}
  end

  @doc "Returns a metric's left and top offsets in pixels."
  def pixel_position(metric) do
    {@padding + coordinate(metric, :x) * @grid_step,
     @padding + coordinate(metric, :y) * @grid_step}
  end

  @doc "The canvas dimensions, including the final card and right/bottom padding."
  def size(metrics) do
    Enum.reduce(metrics, {@minimum_width, @minimum_height}, fn metric, {width, height} ->
      {left, top} = pixel_position(metric)

      {max(width, left + @card_width + @padding), max(height, top + @card_height + @padding)}
    end)
  end

  @doc "Returns a default-spaced empty card slot, checking rectangles rather than origins."
  def free_position(metrics) do
    for y <- 0..@max_y//default_row_step(),
        x <- [0, default_column_step(), 2 * default_column_step()],
        x <= @max_x,
        not Enum.any?(metrics, &overlaps?(&1, x, y)) do
      {x, y}
    end
    |> List.first()
  end

  defp default_column_step, do: div(@legacy_column_step, @grid_step)
  defp default_row_step, do: div(@legacy_row_step + div(@grid_step, 2), @grid_step)

  defp overlaps?(metric, x, y) do
    abs(coordinate(metric, :x) - x) * @grid_step < @card_width and
      abs(coordinate(metric, :y) - y) * @grid_step < @card_height
  end

  defp coordinate(metric, key), do: Map.get(metric, Atom.to_string(key), Map.get(metric, key))
end
