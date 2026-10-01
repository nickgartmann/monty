defmodule Monty.Simulation.PertTest do
  use ExUnit.Case, async: true

  alias Monty.Simulation
  alias Monty.Simulation.Parser

  test "pert is a lowercase, three-argument allowlisted call with ordered references" do
    assert Parser.parse("=pert(Minimum, Mode, Maximum) + Minimum") ==
             {:ok,
              {:formula,
               {:binary, :add,
                {:call, :pert, [{:ref, "Minimum"}, {:ref, "Mode"}, {:ref, "Maximum"}]},
                {:ref, "Minimum"}}}, ["Minimum", "Mode", "Maximum"]}

    for formula <- ["=pert(1, 2)", "=pert(1, 2, 3, 4)"] do
      assert {:error, reason} = Parser.parse(formula)
      assert reason =~ "Invalid number of arguments"
    end

    assert Parser.parse("=PERT(1, 2, 3)") == {:error, "Unknown function: PERT"}

    for formula <- ["=pert([0], 1, 2)", "=pert(0, 1, A[0])", "=pert(0, 1, A.b)"] do
      assert {:error, _} = Parser.parse(formula), formula
    end
  end

  test "fixed-weight beta-PERT has its expected mean and variance, with bounded samples" do
    minimum = 0.0
    mode = 3.0
    maximum = 10.0
    alpha = 1 + 4 * (mode - minimum) / (maximum - minimum)
    beta = 1 + 4 * (maximum - mode) / (maximum - minimum)
    expected_mean = (minimum + 4 * mode + maximum) / 6

    expected_variance =
      (maximum - minimum) ** 2 * alpha * beta / ((alpha + beta) ** 2 * (alpha + beta + 1))

    %{"PERT" => result} =
      Simulation.run([%{key: "PERT", input: "=pert(0, 3, 10)"}],
        samples: 6_000,
        seed: 508
      )

    sample_count = length(result.samples)
    assert sample_count == 6_000
    assert Enum.all?(result.samples, &(&1 >= minimum and &1 <= maximum))
    assert_in_delta result.mean, expected_mean, 0.12

    empirical_variance =
      Enum.reduce(result.samples, 0.0, fn value, total ->
        total + (value - result.mean) ** 2 / sample_count
      end)

    assert_in_delta empirical_variance, expected_variance, 0.35
    assert result.dependencies == []
  end

  test "endpoint modes and signed percentage inputs remain within their bounds" do
    results =
      Simulation.run(
        [
          %{key: "AtMinimum", input: "=pert(-20%, -20%, 30%)"},
          %{key: "AtMaximum", input: "=pert(-20%, 30%, 30%)"},
          %{key: "Signed", input: "=pert(-10, -2, 5)"}
        ],
        samples: 4_000,
        seed: 59
      )

    assert Enum.all?(results["AtMinimum"].samples, &(&1 >= -0.2 and &1 <= 0.3))
    assert Enum.all?(results["AtMaximum"].samples, &(&1 >= -0.2 and &1 <= 0.3))
    assert Enum.all?(results["Signed"].samples, &(&1 >= -10 and &1 <= 5))
    assert_in_delta results["AtMinimum"].mean, (-0.2 * 5 + 0.3) / 6, 0.012
    assert_in_delta results["AtMaximum"].mean, (-0.2 + 0.3 * 5) / 6, 0.012
    assert_in_delta results["Signed"].mean, (-10 + 4 * -2 + 5) / 6, 0.3
  end

  test "explicit seeds repeat without mutating the caller RNG; separate calls draw independently" do
    :rand.seed(:exsss, {11, 22, 33})
    caller_state = Process.get(:rand_seed)

    metrics = [
      %{key: "Difference", input: "=pert(0, 5, 10) - pert(0, 5, 10)"},
      %{key: "Nested", input: "=pert(0, pert(2, 3, 4), 10)"}
    ]

    first = Simulation.run(metrics, samples: 200, seed: {4, 5, 6})
    assert Process.get(:rand_seed) == caller_state
    assert first == Simulation.run(metrics, samples: 200, seed: {4, 5, 6})
    assert Process.get(:rand_seed) == caller_state

    refute first["Difference"].samples ==
             Simulation.run(metrics, samples: 200, seed: {4, 5, 7})["Difference"].samples

    assert Enum.any?(first["Difference"].samples, &(&1 != 0))
    assert Enum.all?(first["Nested"].samples, &(&1 >= 0 and &1 <= 10))
  end

  test "metric parameters resolve forward references with aligned samples" do
    results =
      Simulation.run(
        [
          %{key: "Draw", input: "=pert(Minimum, Mode, Maximum)"},
          %{key: "Difference", input: "=Draw - Draw"},
          %{key: "Minimum", input: "0"},
          %{key: "Mode", input: "=uniform(2, 4)"},
          %{key: "Maximum", input: "=Mode + 6"}
        ],
        samples: 250,
        seed: 19
      )

    assert results["Draw"].dependencies == ["Minimum", "Mode", "Maximum"]
    assert results["Maximum"].samples == Enum.map(results["Mode"].samples, &(&1 + 6))
    assert Enum.all?(results["Difference"].samples, &(&1 == 0))

    assert Enum.zip(results["Draw"].samples, results["Maximum"].samples)
           |> Enum.all?(fn {draw, upper} -> draw >= 0 and draw <= upper end)
  end

  test "invalid bounds and modes isolate failures without interrupting independent metrics" do
    results =
      Simulation.run(
        [
          %{key: "Equal", input: "=pert(10, 10, 10)"},
          %{key: "Reversed", input: "=pert(20, 15, 10)"},
          %{key: "Below", input: "=pert(0, -1, 10)"},
          %{key: "Above", input: "=pert(0, 11, 10)"},
          %{key: "WrongArity", input: "=pert(0, 10)"},
          %{key: "BadSyntax", input: "=pert(0, 1, A[0])"},
          %{key: "Dependent", input: "=pert(0, Equal, 10)"},
          %{key: "Unknown", input: "=pert(0, Missing, 10)"},
          %{key: "Cycle", input: "=pert(0, Cycle, 10)"},
          %{key: "Good", input: "=pert(0, 5, 10)"}
        ],
        samples: 40,
        seed: 17
      )

    assert results["Equal"].error =~ "minimum"
    assert results["Reversed"].error =~ "minimum"
    assert results["Below"].error =~ "mode"
    assert results["Above"].error =~ "mode"
    assert results["WrongArity"].error =~ "arguments"
    assert results["BadSyntax"].error
    assert results["Dependent"].error =~ "Dependency Equal"
    assert results["Unknown"].error =~ "Unknown reference"
    assert results["Cycle"].error =~ "Cyclic reference"
    assert length(results["Good"].samples) == 40
  end

  test "referenced distribution parameters are checked on each draw" do
    results =
      Simulation.run(
        [
          %{key: "Maximum", input: "=uniform(8, 12)"},
          %{key: "Draw", input: "=pert(0, 10, Maximum)"},
          %{key: "Independent", input: "=pert(0, 1, 2)"}
        ],
        samples: 200,
        seed: 4
      )

    assert results["Maximum"].samples |> Enum.any?(&(&1 < 10))
    assert results["Maximum"].samples |> Enum.any?(&(&1 > 10))
    assert results["Draw"].dependencies == ["Maximum"]
    assert results["Draw"].error =~ "mode"
    assert length(results["Independent"].samples) == 200
  end

  test "large same-sign and opposite-sign finite endpoints produce bounded finite samples" do
    results =
      Simulation.run(
        [
          %{key: "Opposite", input: "=pert(-1e308, 0, 1e308)"},
          %{key: "Positive", input: "=pert(1e308, 1.2e308, 1.5e308)"}
        ],
        samples: 120,
        seed: 73
      )

    assert length(results["Opposite"].samples) == 120
    assert Enum.all?(results["Opposite"].samples, &(&1 >= -1.0e308 and &1 <= 1.0e308))
    assert length(results["Positive"].samples) == 120
    assert Enum.all?(results["Positive"].samples, &(&1 >= 1.0e308 and &1 <= 1.5e308))
  end
end
