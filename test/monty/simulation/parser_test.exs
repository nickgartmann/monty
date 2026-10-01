defmodule Monty.Simulation.ParserTest do
  use ExUnit.Case, async: true

  alias Monty.Simulation.Parser

  test "numbers, percentages, scientific notation, and signed intervals retain their shapes" do
    assert Parser.parse("1,234.5") == {:ok, {:constant, 1234.5}, []}
    assert Parser.parse("-12.5%") == {:ok, {:constant, -0.125}, []}
    assert Parser.parse("1e3 to -2.5e2%") == {:ok, {:interval, 1000.0, -2.5}, []}

    assert Parser.parse("=1e3 + .5%") ==
             {:ok, {:formula, {:binary, :add, {:number, 1000.0}, {:number, 0.005}}}, []}
  end

  test "subtraction is not part of an Abacus identifier, and references are ordered unique" do
    assert Parser.parse("=A-B + A*normal") ==
             {:ok,
              {:formula,
               {:binary, :add, {:binary, :subtract, {:ref, "A"}, {:ref, "B"}},
                {:binary, :multiply, {:ref, "A"}, {:ref, "normal"}}}}, ["A", "B", "normal"]}

    assert Parser.parse("=true + null - not") ==
             {:ok,
              {:formula,
               {:binary, :subtract, {:binary, :add, {:ref, "true"}, {:ref, "null"}},
                {:ref, "not"}}}, ["true", "null", "not"]}

    assert Parser.parse("=_monty_name_1 - A") ==
             {:ok, {:formula, {:binary, :subtract, {:ref, "_monty_name_1"}, {:ref, "A"}}},
              ["_monty_name_1", "A"]}
  end

  test "unary signs bind less tightly than right-associative powers and more tightly than multiplication" do
    assert Parser.parse("=-2^2") ==
             {:ok,
              {:formula, {:unary, :subtract, {:binary, :power, {:number, 2.0}, {:number, 2.0}}}},
              []}

    assert Parser.parse("=(-2)^2") ==
             {:ok,
              {:formula, {:binary, :power, {:unary, :subtract, {:number, 2.0}}, {:number, 2.0}}},
              []}

    assert Parser.parse("=2^-3^2") ==
             {:ok,
              {:formula,
               {:binary, :power, {:number, 2.0},
                {:unary, :subtract, {:binary, :power, {:number, 3.0}, {:number, 2.0}}}}}, []}

    assert Parser.parse("=-A^B*C") ==
             {:ok,
              {:formula,
               {:binary, :multiply,
                {:unary, :subtract, {:binary, :power, {:ref, "A"}, {:ref, "B"}}}, {:ref, "C"}}},
              ["A", "B", "C"]}

    assert Parser.parse("=+--sqrt(A)") ==
             {:ok,
              {:formula,
               {:unary, :add,
                {:unary, :subtract, {:unary, :subtract, {:call, :sqrt, [{:ref, "A"}]}}}}}, ["A"]}
  end

  test "only allowlisted calls with valid arities are translated, and functions are not dependencies" do
    for name <- ~w(normal lognormal uniform) do
      function = %{"normal" => :normal, "lognormal" => :lognormal, "uniform" => :uniform}[name]

      assert Parser.parse("=#{name}(A, B)") ==
               {:ok, {:formula, {:call, function, [{:ref, "A"}, {:ref, "B"}]}}, ["A", "B"]}

      assert {:error, error} = Parser.parse("=#{name}(A)")
      assert error =~ "Invalid number of arguments"
    end

    for name <- ~w(sin cos tan floor ceil round abs sqrt log exp) do
      function =
        %{
          "sin" => :sin,
          "cos" => :cos,
          "tan" => :tan,
          "floor" => :floor,
          "ceil" => :ceil,
          "round" => :round,
          "abs" => :abs,
          "sqrt" => :sqrt,
          "log" => :log,
          "exp" => :exp
        }[name]

      assert Parser.parse("=#{name}(A)") ==
               {:ok, {:formula, {:call, function, [{:ref, "A"}]}}, ["A"]}

      assert {:error, error} = Parser.parse("=#{name}(A, B)")
      assert error =~ "Invalid number of arguments"
    end

    assert Parser.parse("=max(A, B) + mean(B, C) + sum(A)") |> elem(2) == ["A", "B", "C"]
    assert Parser.parse("=unexpected(A)") == {:error, "Unknown function: unexpected"}
  end

  test "unsupported syntax is rejected, including Abacus collections, access, and operators" do
    for input <- [
          "=[1, 2]",
          "={a: 2}",
          "=A.b",
          "=A[0]",
          "=2!",
          "=1 & 2",
          "=1 << 2",
          "=A => B",
          "=\"text\"",
          "=true ? A : B",
          "=A ? B : C",
          "=A && B",
          "=1/"
        ] do
      assert {:error, _} = Parser.parse(input), input
    end
  end

  test "bounded input, token count, and nesting depth are enforced" do
    assert {:error, error} = Parser.parse(String.duplicate(" ", 513))
    assert error =~ "512"
    assert {:error, error} = Parser.parse("=" <> Enum.join(List.duplicate("A", 65), "+"))
    assert error =~ "too many tokens"

    assert {:error, error} =
             Parser.parse("=" <> String.duplicate("(", 21) <> "1" <> String.duplicate(")", 21))

    assert error =~ "deeply nested"
    assert {:error, error} = Parser.parse("=" <> Enum.join(List.duplicate("A", 22), "^"))
    assert error =~ "deeply nested"
  end

  test "Abacus process dictionary is restored after successful and failed compilation" do
    Process.put(:variables, %{sentinel: 42})

    try do
      assert {:ok, _, _} = Parser.parse("=A+1")
      assert Process.get(:variables) == %{sentinel: 42}
      assert {:error, _} = Parser.parse("=A+")
      assert Process.get(:variables) == %{sentinel: 42}
    after
      Process.delete(:variables)
    end

    assert {:error, _} = Parser.parse("=A+")
    assert Process.get(:variables) == nil

    Process.put(:variables, nil)

    try do
      assert {:ok, _, _} = Parser.parse("=A+1")
      assert :variables in Process.get_keys()
      assert Process.get(:variables) == nil
    after
      Process.delete(:variables)
    end
  end
end
