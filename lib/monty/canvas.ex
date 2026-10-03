defmodule Monty.Canvas do
  @moduledoc """
  Shared geometry for metric positions. Coordinates are integer indices on a
  20px grid, measured from the canvas's 32px padding.
  """

  @grid_step 20
  @padding 32
  @card_width 240
  @card_height 120
  @card_gap 40
  @link_bend 50
  @legacy_column_step 280
  @legacy_row_step 224

  def grid_step, do: @grid_step
  def padding, do: @padding
  def card_width, do: @card_width
  def card_height, do: @card_height
  def link_bend, do: @link_bend

  @doc "Whether a signed grid coordinate and its pixel position fit browser integer precision."
  def valid_coordinate?(value) do
    is_integer(value) and
      abs(value) <= div(9_007_199_254_740_991 - @padding - @card_width, @grid_step)
  end

  @doc "A comfortably spaced preset slot using the current card dimensions."
  def default_position(column, row) do
    {column * default_column_step(), row * default_row_step()}
  end

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

  @doc "Returns a default-spaced empty card slot, checking rectangles rather than origins."
  def free_position(metrics) do
    Stream.iterate(0, &(&1 + default_row_step()))
    |> Enum.find_value(fn y ->
      Enum.find_value([0, default_column_step(), 2 * default_column_step()], fn x ->
        if Enum.any?(metrics, &overlaps?(&1, x, y)), do: nil, else: {x, y}
      end)
    end)
  end

  defp default_column_step, do: div(@card_width + @card_gap + @grid_step - 1, @grid_step)
  defp default_row_step, do: div(@card_height + @card_gap + @grid_step - 1, @grid_step)

  defp overlaps?(metric, x, y) do
    abs(coordinate(metric, :x) - x) * @grid_step < @card_width and
      abs(coordinate(metric, :y) - y) * @grid_step < @card_height
  end

  defp coordinate(metric, key), do: Map.get(metric, Atom.to_string(key), Map.get(metric, key))
end
