defmodule Monty.SimulationTest do
  use ExUnit.Case, async: true

  alias Monty.Simulation

  test "constants, signed scientific notation, commas and percentages" do
    results =
      Simulation.run(
        [
          %{key: "A", name: "Revenue", id: "uuid", input: " -1,234.5e+2 "},
          %{"key" => "B", "input" => "+25%"},
          %{key: "C", input: ".5e-1"}
        ],
        samples: 3,
        seed: 4
      )

    assert results["A"].samples == [-123_450.0, -123_450.0, -123_450.0]
    assert results["A"].dependencies == []
    assert results["A"].mean == -123_450.0
    assert results["A"].median == -123_450.0
    assert results["A"].low == -123_450.0
    assert results["A"].high == -123_450.0
    assert length(results["A"].histogram) == 20
    assert Enum.sum(results["A"].histogram) == 3
    assert results["B"].samples == [0.25, 0.25, 0.25]
    assert results["C"].samples == [0.05, 0.05, 0.05]
  end

  test "formulas resolve forward references and reuse each shared sample" do
    metrics = [
      %{key: "Double", input: "=A + A"},
      %{key: "Difference", input: "=A - A"},
      %{key: "A", input: "10 to 20"},
      %{key: "Product", input: "=A * Double"},
      %{key: "Mixed", input: "=sum(Product, max(A, 2), mean(A, A))"}
    ]

    results = Simulation.run(metrics, samples: 200, seed: 123)

    assert results["Double"].dependencies == ["A"]
    assert results["Mixed"].dependencies == ["Product", "A"]
    assert Enum.all?(results["Difference"].samples, &(&1 == 0.0))
    assert results["Double"].samples == Enum.map(results["A"].samples, &(&1 * 2))

    assert results["Product"].samples ==
             Enum.zip_with(results["A"].samples, results["Double"].samples, &(&1 * &2))

    assert results == Simulation.run(metrics, samples: 200, seed: 123)
    refute results["A"].samples == Simulation.run(metrics, samples: 200, seed: 124)["A"].samples

    assert Simulation.run(metrics, samples: 200, seed: {41, 72, 19}) ==
             Simulation.run(metrics, samples: 200, seed: {41, 72, 19})
  end

  test "parentheses, power associativity, unary precedence and whitelisted functions" do
    metrics = [
      %{key: "A", input: "=2^3^2"},
      %{key: "B", input: "=-2^2 + (3 + 5) / 2"},
      %{key: "C", input: "=min(4, 3) + max(2, 5) + abs(-3) + sqrt(9) + log(exp(1))"},
      %{key: "D", input: "=mean(2, 4, 6) + sum(1, 2, 3)"}
    ]

    results = Simulation.run(metrics, samples: 1, seed: 1)
    assert_in_delta results["A"].mean, 512.0, 1.0e-9
    assert_in_delta results["B"].mean, 0.0, 1.0e-9
    assert_in_delta results["C"].mean, 15.0, 1.0e-9
    assert_in_delta results["D"].mean, 10.0, 1.0e-9
  end

  test "normal interval is a 90% confidence interval, uniform bounds are full" do
    results =
      Simulation.run(
        [
          %{key: "Normal", input: "10 to 20"},
          %{key: "Uniform", input: "10 to 20", distribution: "uniform"}
        ],
        samples: 5_000,
        seed: 82
      )

    assert_in_delta results["Normal"].mean, 15.0, 0.2
    assert_in_delta results["Normal"].low, 10.0, 0.3
    assert_in_delta results["Normal"].high, 20.0, 0.3
    assert_in_delta results["Uniform"].mean, 15.0, 0.2
    assert_in_delta results["Uniform"].low, 10.5, 0.3
    assert_in_delta results["Uniform"].high, 19.5, 0.3
    assert Enum.all?(results["Uniform"].samples, &(&1 >= 10.0 and &1 <= 20.0))
    assert Enum.sum(results["Uniform"].histogram) == 5_000
  end

  test "lognormal bounds are percentiles and cannot include zero" do
    results =
      Simulation.run(
        [
          %{key: "Valid", input: "10 to 40", distribution: "lognormal"},
          %{key: "Invalid", input: "0 to 10", distribution: "lognormal"},
          %{key: "Reverse", input: "20 to 10", distribution: "uniform"}
        ],
        samples: 5_000,
        seed: 82
      )

    assert_in_delta results["Valid"].median, 20.0, 0.5
    assert_in_delta results["Valid"].low, 10.0, 0.5
    assert_in_delta results["Valid"].high, 40.0, 1.0
    assert Enum.all?(results["Valid"].samples, &(&1 > 0.0))
    assert results["Invalid"].error =~ "positive"
    assert results["Reverse"].error =~ "lower bound"
  end

  test "signed percentage ranges and fractional formulas" do
    results =
      Simulation.run(
        [
          %{key: "Fraction", input: "-10% to +20%", distribution: "uniform"},
          %{key: "Scaled", input: "=Fraction * 1,000 + 5%"}
        ],
        samples: 50,
        seed: {41, 72, 19}
      )

    assert Enum.all?(results["Fraction"].samples, &(&1 >= -0.1 and &1 <= 0.2))

    assert Enum.zip(results["Fraction"].samples, results["Scaled"].samples)
           |> Enum.all?(fn {fraction, scaled} ->
             abs(scaled - (fraction * 1_000 + 0.05)) < 1.0e-9
           end)
  end

  test "invalid formulas, unknown references, cycles, and dependents are isolated" do
    results =
      Simulation.run(
        [
          %{key: "A", input: "=B + 1"},
          %{key: "B", input: "=A * 2"},
          %{key: "Missing", input: "=NotHere"},
          %{key: "Broken", input: "=sqrt("},
          %{key: "After", input: "=Broken + 1"},
          %{key: "Good", input: "12"}
        ],
        samples: 2,
        seed: 4
      )

    assert results["A"].dependencies == ["B"]
    assert results["B"].dependencies == ["A"]
    assert results["A"].error =~ "Cyclic reference"
    assert results["B"].error =~ "Cyclic reference"
    assert results["Missing"].dependencies == ["NotHere"]
    assert results["Missing"].error =~ "Unknown reference: NotHere"
    assert results["Broken"].error =~ "Invalid formula"
    assert results["After"].dependencies == ["Broken"]
    assert results["After"].error =~ "Dependency Broken"
    assert results["Good"].samples == [12.0, 12.0]
  end

  test "division, domain errors and overflow are per-metric errors" do
    results =
      Simulation.run(
        [
          %{key: "Zero", input: "=1 / 0"},
          %{key: "Root", input: "=sqrt(-1)"},
          %{key: "Log", input: "=log(0)"},
          %{key: "Overflow", input: "=1e308 * 1e308"},
          %{key: "InputOverflow", input: "1e999"},
          %{
            key: "Extreme",
            input: "-1.7976931348623157e308 to 1.7976931348623157e308",
            distribution: "uniform"
          },
          %{key: "OK", input: "42"}
        ],
        samples: 2,
        seed: 1
      )

    assert results["Zero"].error =~ "Division by zero"
    assert results["Root"].error =~ "arithmetic"
    assert results["Log"].error =~ "arithmetic"
    assert results["Overflow"].error =~ "arithmetic"
    assert results["InputOverflow"].error =~ "number"
    assert Enum.sum(results["Extreme"].histogram) == 2
    assert results["OK"].mean == 42.0
  end

  test "unsafe input is rejected without evaluation or dynamic atom creation" do
    inputs = [
      "=System.cmd(\"touch\", [\"/tmp/unsafe\"])",
      "=__ENV__",
      "=A |> IO.inspect()",
      "=foo(1)",
      "=1; 2",
      "=1 + :secret",
      "=min()"
    ]

    results =
      inputs
      |> Enum.with_index(1)
      |> Enum.map(fn {input, index} -> %{key: "X#{index}", input: input} end)
      |> Simulation.run(samples: 1, seed: 1)

    assert Enum.all?(results, fn {_key, result} -> is_binary(result.error) end)

    unknown = "Missing_#{System.unique_integer([:positive])}"

    assert Simulation.run([%{key: "A", input: "=#{unknown}"}], samples: 1)["A"].error =~
             "Unknown reference"

    assert_raise ArgumentError, fn -> String.to_existing_atom(unknown) end
  end

  test "input, parser depth, token, metric and sample limits are enforced" do
    results =
      Simulation.run(
        [
          %{key: "Long", input: String.duplicate("1", 513)},
          %{
            key: "Deep",
            input: "=" <> String.duplicate("(", 21) <> "1" <> String.duplicate(")", 21)
          },
          %{key: "Tokens", input: "=" <> Enum.join(List.duplicate("1", 70), "+")}
        ],
        samples: 1
      )

    assert results["Long"].error =~ "512"
    assert results["Deep"].error =~ "deeply nested"
    assert results["Tokens"].error =~ "too many tokens"

    assert Simulation.run([%{key: "A", input: "1"}], samples: 0)["_error"].error =~ "Samples"
    assert Simulation.run([%{key: "A", input: "1"}], samples: 10_001)["_error"].error =~ "Samples"

    metrics = Enum.map(1..101, &%{key: "M#{&1}", input: "1"})
    assert Simulation.run(metrics)["_error"].error =~ "100"
  end

  test "duplicate and invalid keys or distributions do not crash" do
    results =
      Simulation.run(
        [
          %{key: "A", input: "1"},
          %{"key" => "A", "input" => "2"},
          %{key: "with space", input: "3"},
          %{input: "4"},
          %{key: "BadDistribution", input: "10 to 20", distribution: "triangular"}
        ],
        samples: 1
      )

    assert results["A"].error =~ "Duplicate"
    assert results["with space"].error =~ "Invalid metric key"
    assert results["#metric_4"].error =~ "Invalid metric key"
    assert results["BadDistribution"].error =~ "Unknown distribution"
  end
end
