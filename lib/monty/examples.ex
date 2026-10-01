defmodule Monty.Examples do
  @moduledoc """
  Original, runnable examples for exploring Monty without an account.
  """

  def all do
    [
      %{
        title: "How long is our startup runway?",
        description:
          "A little uncertainty goes a long way. Model cash, revenue, and monthly costs to understand how much time a startup really has.",
        visibility: :public,
        metrics: [
          preset_metric("A", "Cash in the bank", "450000", 0, 0),
          preset_metric("B", "Monthly revenue", "18000 to 32000", 0, 1),
          preset_metric("C", "Monthly costs", "45000 to 65000", 1, 0),
          preset_metric("D", "Monthly burn", "=C - B", 1, 1),
          preset_metric("E", "Runway in months", "=A / D", 2, 1)
        ]
      },
      %{
        title: "What could this launch earn?",
        description:
          "Connect visitors, conversion, and price. Explore the range of possible outcomes instead of betting on a single forecast.",
        visibility: :public,
        metrics: [
          preset_metric("A", "Launch visitors", "10000 to 25000", 0, 0, "lognormal"),
          preset_metric("B", "Conversion rate", "2% to 5%", 0, 1, "uniform"),
          preset_metric("C", "New customers", "=A * B", 1, 0),
          preset_metric("D", "Price per customer", "49", 1, 1),
          preset_metric("E", "Launch revenue", "=C * D", 2, 0)
        ]
      },
      %{
        title: "The real cost of a project",
        description:
          "Estimate research, design, and implementation time, then turn those uncertainties into a realistic project budget.",
        visibility: :public,
        metrics: [
          preset_metric("A", "Research hours", "12 to 24", 0, 0),
          preset_metric("B", "Design hours", "30 to 60", 0, 1),
          preset_metric("C", "Build hours", "80 to 160", 0, 2, "lognormal"),
          preset_metric("D", "Total hours", "=A + B + C", 1, 1),
          preset_metric("E", "Hourly rate", "85", 1, 2),
          preset_metric("F", "Project budget", "=D * E", 2, 1)
        ]
      }
    ]
  end

  def demo, do: List.first(all())

  def starter_metrics do
    [
      preset_metric("A", "Monthly visitors", "1000 to 2000", 0, 0),
      preset_metric("B", "Conversion rate", "2% to 5%", 0, 1, "uniform"),
      preset_metric("C", "Customers", "=A * B", 1, 0)
    ]
  end

  # Keep presets spaced like the original layouts; movement itself uses dot indices.
  defp preset_metric(key, name, input, column, row, distribution \\ "normal") do
    {x, y} = Monty.Canvas.from_legacy_position(column, row)
    metric(key, name, input, x, y, distribution)
  end

  @doc "Builds a metric at fine dot-grid indices (20 pixels per x/y increment)."
  def metric(key, name, input, x, y, distribution \\ "normal") do
    %{
      "id" => Ecto.UUID.generate(),
      "key" => key,
      "name" => name,
      "input" => input,
      "distribution" => distribution,
      "notes" => "",
      "x" => x,
      "y" => y
    }
  end
end
