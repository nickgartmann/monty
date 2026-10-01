defmodule Monty.Simulation.Parser do
  @moduledoc false

  @max_input 512
  @max_tokens 128
  @max_depth 20
  @number ~r/\A(?:(?:\d{1,3}(?:,\d{3})+|\d+)(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?%?/
  @identifier ~r/\A[A-Za-z_][A-Za-z0-9_]*/
  @operators %{"+" => :add, "-" => :subtract, "*" => :multiply, "/" => :divide, "^" => :power}
  @functions %{
    "min" => :min,
    "max" => :max,
    "abs" => :abs,
    "sqrt" => :sqrt,
    "log" => :log,
    "exp" => :exp,
    "mean" => :mean,
    "sum" => :sum
  }

  @doc """
  Parses a bounded metric input. Bare inputs are numbers or `lower to upper`;
  expressions require `=`. Returns an AST and ordered, unique references.
  """
  def parse(input) when is_binary(input) and byte_size(input) <= @max_input do
    input = String.trim(input)

    case input do
      "=" <> expression ->
        with {:ok, tokens} <- tokenize(expression),
             {:ok, ast, []} <- expression(tokens, 0, 0) do
          {:ok, {:formula, ast}, dependencies(ast)}
        else
          {:ok, _, _} -> {:error, "Invalid formula"}
          {:error, _} = error -> error
        end

      _ ->
        with {:ok, tokens} <- tokenize(input) do
          case tokens do
            [{:number, number}] -> {:ok, {:constant, number}, []}
            [:subtract, {:number, number}] -> {:ok, {:constant, -number}, []}
            [:add, {:number, number}] -> {:ok, {:constant, number}, []}
            _ -> interval(tokens)
          end
        end
    end
  end

  def parse(_), do: {:error, "Input must be text of at most #{@max_input} bytes"}

  defp interval(tokens) do
    with {:ok, low, [{:identifier, "to"} | rest]} <- signed_number(tokens),
         {:ok, high, []} <- signed_number(rest) do
      {:ok, {:interval, low, high}, []}
    else
      _ -> {:error, "Expected a number, a range like 10 to 20, or a formula starting with ="}
    end
  end

  defp signed_number([{:number, number} | rest]), do: {:ok, number, rest}
  defp signed_number([:subtract, {:number, number} | rest]), do: {:ok, -number, rest}
  defp signed_number([:add, {:number, number} | rest]), do: {:ok, number, rest}
  defp signed_number(_), do: {:error, "Expected a number"}

  defp tokenize(input), do: tokenize(input, [], 0)

  defp tokenize(<<>>, tokens, _count), do: {:ok, Enum.reverse(tokens)}
  defp tokenize(_, _, @max_tokens), do: {:error, "Input has too many tokens"}

  defp tokenize(<<char, rest::binary>>, tokens, count) when char in [?\s, ?\t, ?\r, ?\n],
    do: tokenize(rest, tokens, count)

  defp tokenize(input, tokens, count) do
    cond do
      match = Regex.run(@number, input) ->
        [raw] = match

        with {:ok, number} <- number(raw) do
          tokenize(
            binary_part(input, byte_size(raw), byte_size(input) - byte_size(raw)),
            [
              {:number, number} | tokens
            ],
            count + 1
          )
        end

      match = Regex.run(@identifier, input) ->
        [raw] = match

        tokenize(
          binary_part(input, byte_size(raw), byte_size(input) - byte_size(raw)),
          [
            {:identifier, raw} | tokens
          ],
          count + 1
        )

      true ->
        case input do
          <<char, rest::binary>> when char in ~c"+-*/^()," ->
            token =
              case <<char>> do
                "(" -> :open
                ")" -> :close
                "," -> :comma
                operator -> Map.fetch!(@operators, operator)
              end

            tokenize(rest, [token | tokens], count + 1)

          _ ->
            {:error, "Invalid character in input"}
        end
    end
  end

  defp number(raw) do
    percentage? = String.ends_with?(raw, "%")

    numeric =
      raw
      |> String.trim_trailing("%")
      |> String.replace(",", "")
      |> then(&Regex.replace(~r/\A\./, &1, "0."))
      |> then(&Regex.replace(~r/\.(?=[eE]|\z)/, &1, ".0"))

    try do
      case Float.parse(numeric) do
        {number, ""}
        when number <= 1.7976931348623157e308 and number >= -1.7976931348623157e308 ->
          {:ok, if(percentage?, do: number / 100.0, else: number)}

        _ ->
          {:error, "Invalid or non-finite number"}
      end
    rescue
      ArgumentError -> {:error, "Invalid or non-finite number"}
    end
  end

  defp expression(_, _, depth) when depth > @max_depth,
    do: {:error, "Formula is too deeply nested"}

  defp expression(tokens, precedence, depth) do
    with {:ok, left, rest} <- prefix(tokens, depth + 1) do
      infix(left, rest, precedence, depth)
    end
  end

  defp prefix([{:number, number} | rest], _depth), do: {:ok, {:number, number}, rest}

  defp prefix([{:identifier, name}, :open | rest], depth) do
    case Map.fetch(@functions, name) do
      {:ok, function} ->
        with {:ok, args, remaining} <- arguments(rest, depth) do
          if valid_arity?(function, length(args)),
            do: {:ok, {:call, function, args}, remaining},
            else: {:error, "Invalid number of arguments for #{name}"}
        end

      :error ->
        {:error, "Unknown function: #{name}"}
    end
  end

  defp prefix([{:identifier, name} | rest], _depth), do: {:ok, {:ref, name}, rest}

  defp prefix([op | rest], depth) when op in [:add, :subtract] do
    with {:ok, ast, remaining} <- expression(rest, 4, depth) do
      {:ok, {:unary, op, ast}, remaining}
    end
  end

  defp prefix([:open | rest], depth) do
    case expression(rest, 0, depth) do
      {:ok, ast, [:close | remaining]} -> {:ok, ast, remaining}
      {:error, _} = error -> error
      _ -> {:error, "Expected closing parenthesis"}
    end
  end

  defp prefix(_, _depth), do: {:error, "Invalid formula"}

  defp arguments([:close | rest], _depth), do: {:ok, [], rest}

  defp arguments(tokens, depth) do
    with {:ok, ast, rest} <- expression(tokens, 0, depth) do
      case rest do
        [:comma | following] ->
          with {:ok, others, remaining} <- arguments(following, depth) do
            {:ok, [ast | others], remaining}
          end

        [:close | following] ->
          {:ok, [ast], following}

        _ ->
          {:error, "Expected comma or closing parenthesis"}
      end
    end
  end

  defp infix(left, [op | rest] = tokens, minimum, depth) do
    precedence = operator_precedence(op)

    if precedence >= minimum do
      next_minimum = if op == :power, do: precedence, else: precedence + 1

      with {:ok, right, remaining} <- expression(rest, next_minimum, depth + 1) do
        infix({:binary, op, left, right}, remaining, minimum, depth)
      end
    else
      {:ok, left, tokens}
    end
  end

  defp infix(left, [], _minimum, _depth), do: {:ok, left, []}

  defp operator_precedence(op) when op in [:add, :subtract], do: 2
  defp operator_precedence(op) when op in [:multiply, :divide], do: 3
  defp operator_precedence(:power), do: 4
  defp operator_precedence(_), do: -1

  defp valid_arity?(function, n) when function in [:abs, :sqrt, :log, :exp], do: n == 1
  defp valid_arity?(function, n) when function in [:min, :max], do: n >= 2
  defp valid_arity?(function, n) when function in [:mean, :sum], do: n >= 1

  defp dependencies(ast), do: ast |> references([]) |> Enum.reverse() |> Enum.uniq()
  defp references({:ref, key}, acc), do: [key | acc]
  defp references({:unary, _, ast}, acc), do: references(ast, acc)
  defp references({:binary, _, left, right}, acc), do: references(right, references(left, acc))
  defp references({:call, _, args}, acc), do: Enum.reduce(args, acc, &references/2)
  defp references(_, acc), do: acc
end
