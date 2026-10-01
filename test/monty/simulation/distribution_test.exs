defmodule Monty.Simulation.DistributionTest do
  use ExUnit.Case, async: true

  alias Monty.Simulation

  test "explicit normal and lognormal parameters describe the expected distributions" do
    results =
      Simulation.run(
        [
          %{key: "Normal", input: "=normal(100, 15)"},
          %{key: "Lognormal", input: "=lognormal(0, 1)"},
          %{key: "Uniform", input: "=uniform(-10%, 20%)"}
        ],
        samples: 5_000,
        seed: 82
      )

    assert_in_delta results["Normal"].mean, 100.0, 0.6
    assert_in_delta results["Normal"].low, 100.0 - 15.0 * 1.6448536269514722, 1.0
    assert_in_delta results["Normal"].high, 100.0 + 15.0 * 1.6448536269514722, 1.0
    assert_in_delta results["Lognormal"].median, 1.0, 0.06
    assert_in_delta results["Lognormal"].low, :math.exp(-1.6448536269514722), 0.03
    assert_in_delta results["Lognormal"].high, :math.exp(1.6448536269514722), 0.5
    assert Enum.all?(results["Lognormal"].samples, &(&1 > 0))
    assert Enum.all?(results["Uniform"].samples, &(&1 >= -0.1 and &1 <= 0.2))
    assert results["Normal"].dependencies == []
  end

  test "formula parameters resolve forward references and preserve sample correlation" do
    metrics = [
      %{key: "Draw", input: "=normal(Mean, SD) + Offset"},
      %{key: "Mean", input: "=uniform(10, 20)"},
      %{key: "SD", input: "0"},
      %{key: "Offset", input: "2"},
      %{key: "Difference", input: "=Draw-Draw"}
    ]

    results = Simulation.run(metrics, samples: 200, seed: 123)
    assert results["Draw"].dependencies == ["Mean", "SD", "Offset"]
    assert results["Draw"].samples == Enum.map(results["Mean"].samples, &(&1 + 2))
    assert Enum.all?(results["Difference"].samples, &(&1 == 0))
    assert results == Simulation.run(metrics, samples: 200, seed: 123)

    refute results["Mean"].samples ==
             Simulation.run(metrics, samples: 200, seed: 124)["Mean"].samples
  end

  test "separate and nested calls make fresh deterministic draws without touching the caller RNG" do
    :rand.seed(:exsss, {1, 2, 3})
    caller_state = Process.get(:rand_seed)

    metrics = [
      %{key: "Difference", input: "=normal(0, 1) - normal(0, 1)"},
      %{key: "Nested", input: "=normal(uniform(10, 20), 0)"}
    ]

    results = Simulation.run(metrics, samples: 100, seed: {41, 72, 19})
    assert results == Simulation.run(metrics, samples: 100, seed: {41, 72, 19})
    assert Process.get(:rand_seed) == caller_state
    assert Enum.any?(results["Difference"].samples, &(&1 != 0))
    assert Enum.all?(results["Nested"].samples, &(&1 >= 10 and &1 <= 20))
  end

  test "range and explicit definitions share their sampler, and selectors do not override calls" do
    for {distribution, expression} <- [
          {"uniform", "=uniform(10, 20)"},
          {"normal", "=normal(15, (10 - 5) / 1.6448536269514722)"}
        ] do
      range =
        Simulation.run(
          [%{key: "A", input: "10 to 20", distribution: distribution}],
          samples: 100,
          seed: 123
        )

      explicit =
        Simulation.run(
          [%{key: "A", input: expression, distribution: "lognormal"}],
          samples: 100,
          seed: 123
        )

      assert range == explicit
    end
  end

  test "invalid parameters, arity, arithmetic, and dependents are isolated" do
    results =
      Simulation.run(
        [
          %{key: "Negative", input: "=normal(0, -1)"},
          %{key: "LogNegative", input: "=lognormal(0, -1)"},
          %{key: "Bounds", input: "=uniform(20, 10)"},
          %{key: "Equal", input: "=uniform(10, 10)"},
          %{key: "Arity", input: "=normal(0)"},
          %{key: "Overflow", input: "=lognormal(1e308, 0)"},
          %{key: "Dependent", input: "=normal(Bounds, 1)"},
          %{key: "Missing", input: "=normal(Unknown, 1)"},
          %{key: "Cycle", input: "=uniform(0, Cycle)"},
          %{key: "Good", input: "=normal(42, 0)"},
          %{key: "LogPoint", input: "=lognormal(0, 0)"}
        ],
        samples: 2,
        seed: 1
      )

    assert results["Negative"].error =~ "Standard deviation"
    assert results["LogNegative"].error =~ "Standard deviation"
    assert results["Bounds"].error =~ "lower bound"
    assert results["Equal"].error =~ "lower bound"
    assert results["Arity"].error =~ "arguments"
    assert results["Overflow"].error =~ "arithmetic"
    assert results["Dependent"].error =~ "Dependency Bounds"
    assert results["Missing"].error =~ "Unknown reference"
    assert results["Cycle"].error =~ "Cyclic reference"
    assert results["Good"].samples == [42.0, 42.0]
    assert results["LogPoint"].samples == [1.0, 1.0]
  end

  test "parameters are validated for each draw, not only at compile time" do
    results =
      Simulation.run(
        [
          %{key: "SD", input: "=uniform(-2, -1)"},
          %{key: "Draw", input: "=normal(0, SD)"},
          %{key: "Independent", input: "=uniform(10, 20)"}
        ],
        samples: 50,
        seed: 1
      )

    assert results["Draw"].dependencies == ["SD"]
    assert results["Draw"].error =~ "Standard deviation"
    assert length(results["Independent"].samples) == 50
  end

  test "additional scalar math functions compose with distribution calls" do
    results =
      Simulation.run(
        [
          %{
            key: "A",
            input: "=sin(0) + cos(0) + tan(0) + floor(1.9) + ceil(1.1) + round(normal(2.5, 0))"
          }
        ],
        samples: 1,
        seed: 1
      )

    assert results["A"].samples == [7.0]
  end
end
