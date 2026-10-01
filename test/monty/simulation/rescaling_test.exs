defmodule Monty.Simulation.RescalingTest do
  use ExUnit.Case, async: true

  alias Monty.Simulation

  test "bounded distributions preserve their sampled weights when rescaled to subnormal bounds" do
    for {unit_input, tiny_input} <- [
          {"=pert(0, 0, 1)", "=pert(5e-324, 5e-324, 1e-323)"},
          {"=uniform(0, 1)", "=uniform(5e-324, 1e-323)"}
        ] do
      unit = Simulation.run([%{key: "A", input: unit_input}], samples: 10_000, seed: 42)["A"]
      tiny = Simulation.run([%{key: "A", input: tiny_input}], samples: 10_000, seed: 42)["A"]
      low = 5.0e-324
      high = 1.0e-323

      assert tiny.samples ==
               Enum.map(unit.samples, fn weight -> low + (high - low) * weight end)

      assert Enum.count(tiny.samples, &(&1 == high)) ==
               Enum.count(unit.samples, &(&1 > 0.5))
    end
  end
end
