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
          metric("A", "Cash in the bank", "450000", 0, 0),
          metric("B", "Monthly revenue", "18000 to 32000", 0, 1),
          metric("C", "Monthly costs", "45000 to 65000", 1, 0),
          metric("D", "Monthly burn", "=C - B", 1, 1),
          metric("E", "Runway in months", "=A / D", 2, 1)
        ]
      },
      %{
        title: "What could this launch earn?",
        description:
          "Connect visitors, conversion, and price. Explore the range of possible outcomes instead of betting on a single forecast.",
        visibility: :public,
        metrics: [
          metric("A", "Launch visitors", "10000 to 25000", 0, 0, "lognormal"),
          metric("B", "Conversion rate", "2% to 5%", 0, 1, "uniform"),
          metric("C", "New customers", "=A * B", 1, 0),
          metric("D", "Price per customer", "49", 1, 1),
          metric("E", "Launch revenue", "=C * D", 2, 0)
        ]
      },
      %{
        title: "The real cost of a project",
        description:
          "Estimate research, design, and implementation time, then turn those uncertainties into a realistic project budget.",
        visibility: :public,
        metrics: [
          metric("A", "Research hours", "12 to 24", 0, 0),
          metric("B", "Design hours", "30 to 60", 0, 1),
          metric("C", "Build hours", "80 to 160", 0, 2, "lognormal"),
          metric("D", "Total hours", "=A + B + C", 1, 1),
          metric("E", "Hourly rate", "85", 1, 2),
          metric("F", "Project budget", "=D * E", 2, 1)
        ]
      }
    ]
  end

  def demo, do: List.first(all())

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
