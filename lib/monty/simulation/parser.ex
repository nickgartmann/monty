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
    "sum" => :sum,
    "normal" => :normal,
    "lognormal" => :lognormal,
    "uniform" => :uniform,
    "pert" => :pert,
    "sin" => :sin,
    "cos" => :cos,
    "tan" => :tan,
    "floor" => :floor,
    "ceil" => :ceil,
    "round" => :round
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
             {:ok, source, literals, identifiers, unary} <- prepare_formula(tokens, expression),
             {:ok, compiled, variables} <- compile(source),
             {:ok, ast} <- translate(compiled, invert(variables, identifiers), literals, unary) do
          {:ok, {:formula, ast}, dependencies(ast)}
        else
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

  # Abacus does not accept exponent notation or percentages and interprets a
  # leading minus as part of a number. Literals become private variable names,
  # while unary signs are wrapped around the entire power operand. Spaces
  # between all tokens also prevent Abacus from lexing A-B as one identifier.
  defp prepare_formula(tokens, original) do
    prefix = private_prefix(original, "_monty_")

    {tokens, {literals, identifiers}} =
      tokens
      |> Enum.with_index()
      |> Enum.map_reduce({%{}, %{}}, fn
        {{:number, value}, index}, {values, identifiers} ->
          name = "#{prefix}number_#{index}"
          {{:identifier, name}, {Map.put(values, name, value), identifiers}}

        {{:identifier, original}, index}, {values, identifiers} ->
          name = "#{prefix}name_#{index}"
          {{:identifier, name}, {values, Map.put(identifiers, name, original)}}

        {token, _index}, state ->
          {token, state}
      end)

    unary = %{"#{prefix}positive" => :add, "#{prefix}negative" => :subtract}

    with {:ok, parts} <- normalize(tokens, unary, 0) do
      {:ok, Enum.join(parts, " "), literals, identifiers, unary}
    end
  end

  defp private_prefix(source, prefix) do
    if String.contains?(source, prefix),
      do: private_prefix(source, prefix <> "_"),
      else: prefix
  end

  defp normalize(tokens, unary, depth), do: normalize(tokens, unary, depth, true, [])

  defp normalize([], _unary, _depth, _expect_operand, acc), do: {:ok, Enum.reverse(acc)}

  defp normalize([sign | rest], unary, depth, true, acc) when sign in [:add, :subtract] do
    with {:ok, operand, remaining} <- signed_power([sign | rest], unary, depth) do
      normalize(remaining, unary, depth, false, [operand | acc])
    end
  end

  defp normalize([{:identifier, _} | _] = tokens, unary, depth, _expect_operand, acc) do
    with {:ok, operand, remaining} <- signed_power(tokens, unary, depth) do
      normalize(remaining, unary, depth, false, [operand | acc])
    end
  end

  defp normalize([:open | _] = tokens, unary, depth, _expect_operand, acc) do
    with {:ok, operand, remaining} <- signed_power(tokens, unary, depth) do
      normalize(remaining, unary, depth, false, [operand | acc])
    end
  end

  defp normalize([token | rest], unary, depth, _expect_operand, acc) do
    normalize(
      rest,
      unary,
      depth,
      token in [:comma, :add, :subtract, :multiply, :divide, :power],
      [token_text(token) | acc]
    )
  end

  defp signed_power(_, _, depth) when depth > @max_depth,
    do: {:error, "Formula is too deeply nested"}

  defp signed_power([sign | rest], unary, depth) when sign in [:add, :subtract] do
    with {:ok, operand, remaining} <- signed_power(rest, unary, depth + 1) do
      name = Enum.find_value(unary, fn {name, op} -> if op == sign, do: name end)
      {:ok, "#{name} ( #{operand} )", remaining}
    end
  end

  defp signed_power(tokens, unary, depth) do
    with {:ok, base, rest} <- primary(tokens, unary, depth) do
      case rest do
        [:power | following] ->
          with {:ok, exponent, remaining} <- signed_power(following, unary, depth + 1) do
            {:ok, "#{base} ^ #{exponent}", remaining}
          end

        _ ->
          {:ok, base, rest}
      end
    end
  end

  defp primary([{:identifier, name}, :open | rest], unary, depth) do
    with {:ok, group, remaining} <- group(rest, unary, depth + 1) do
      {:ok, name <> " " <> group, remaining}
    end
  end

  defp primary([{:identifier, name} | rest], _unary, _depth), do: {:ok, name, rest}

  defp primary([:open | rest], unary, depth), do: group(rest, unary, depth + 1)
  defp primary(_, _, _), do: {:error, "Invalid formula"}

  defp group(_, _, depth) when depth > @max_depth,
    do: {:error, "Formula is too deeply nested"}

  defp group(tokens, unary, depth) do
    with {:ok, inside, remaining} <- split_group(tokens, 0, []),
         {:ok, parts} <- normalize(inside, unary, depth) do
      {:ok, "( " <> Enum.join(parts, " ") <> " )", remaining}
    end
  end

  defp split_group([:close | rest], 0, acc), do: {:ok, Enum.reverse(acc), rest}
  defp split_group([:open | rest], depth, acc), do: split_group(rest, depth + 1, [:open | acc])
  defp split_group([:close | rest], depth, acc), do: split_group(rest, depth - 1, [:close | acc])
  defp split_group([token | rest], depth, acc), do: split_group(rest, depth, [token | acc])
  defp split_group([], 0, []), do: {:error, "Invalid formula"}
  defp split_group([], _, _), do: {:error, "Expected closing parenthesis"}

  defp token_text({:identifier, name}), do: name
  defp token_text(:open), do: "("
  defp token_text(:close), do: ")"
  defp token_text(:comma), do: ","

  defp token_text(operator),
    do: operator |> then(&Enum.find(@operators, fn {_, op} -> op == &1 end)) |> elem(0)

  defp compile(source) do
    had_variables? = :variables in Process.get_keys()
    previous = Process.get(:variables)

    try do
      case Abacus.compile(source) do
        {:ok, _, _} = result -> result
        _ -> {:error, "Invalid formula"}
      end
    rescue
      _ -> {:error, "Invalid formula"}
    catch
      _, _ -> {:error, "Invalid formula"}
    after
      if had_variables?,
        do: Process.put(:variables, previous),
        else: Process.delete(:variables)
    end
  end

  defp invert(variables, identifiers) do
    Map.new(variables, fn {name, symbol} -> {symbol, Map.get(identifiers, name, name)} end)
  end

  defp translate(value, _names, _literals, _unary) when is_number(value),
    do: {:ok, {:number, value}}

  defp translate({symbol, _, nil}, names, literals, _unary) when is_atom(symbol) do
    case Map.fetch(names, symbol) do
      {:ok, name} ->
        case Map.fetch(literals, name) do
          {:ok, value} -> {:ok, {:number, value}}
          :error -> {:ok, {:ref, name}}
        end

      :error ->
        {:error, "Invalid formula"}
    end
  end

  defp translate({operator, _, [left, right]}, names, literals, unary)
       when operator in [:+, :-, :*, :/] do
    with {:ok, left} <- translate(left, names, literals, unary),
         {:ok, right} <- translate(right, names, literals, unary) do
      {:ok, {:binary, Map.fetch!(@operators, Atom.to_string(operator)), left, right}}
    end
  end

  defp translate({{:., _, [:math, :pow]}, _, [left, right]}, names, literals, unary) do
    with {:ok, left} <- translate(left, names, literals, unary),
         {:ok, right} <- translate(right, names, literals, unary) do
      {:ok, {:binary, :power, left, right}}
    end
  end

  defp translate({{:., _, [{symbol, _, nil}]}, _, args}, names, literals, unary)
       when is_atom(symbol) and is_list(args) do
    with {:ok, name} <- Map.fetch(names, symbol) do
      cond do
        Map.has_key?(unary, name) and length(args) == 1 ->
          with {:ok, argument} <- translate(hd(args), names, literals, unary) do
            {:ok, {:unary, Map.fetch!(unary, name), argument}}
          end

        Map.has_key?(unary, name) ->
          {:error, "Invalid formula"}

        Map.has_key?(@functions, name) ->
          function = Map.fetch!(@functions, name)

          if valid_arity?(function, length(args)) do
            with {:ok, arguments} <- translate_args(args, names, literals, unary) do
              {:ok, {:call, function, arguments}}
            end
          else
            {:error, "Invalid number of arguments for #{name}"}
          end

        true ->
          {:error, "Unknown function: #{name}"}
      end
    else
      :error -> {:error, "Invalid formula"}
    end
  end

  defp translate(_, _, _, _), do: {:error, "Invalid formula"}

  defp translate_args(args, names, literals, unary) do
    Enum.reduce_while(args, {:ok, []}, fn argument, {:ok, acc} ->
      case translate(argument, names, literals, unary) do
        {:ok, ast} -> {:cont, {:ok, [ast | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, reversed} -> {:ok, Enum.reverse(reversed)}
      error -> error
    end
  end

  defp valid_arity?(function, n)
       when function in [:abs, :sqrt, :log, :exp, :sin, :cos, :tan, :floor, :ceil, :round],
       do: n == 1

  defp valid_arity?(function, n) when function in [:normal, :lognormal, :uniform], do: n == 2
  defp valid_arity?(:pert, n), do: n == 3
  defp valid_arity?(function, n) when function in [:min, :max], do: n >= 2
  defp valid_arity?(function, n) when function in [:mean, :sum], do: n >= 1

  defp dependencies(ast), do: ast |> references([]) |> Enum.reverse() |> Enum.uniq()
  defp references({:ref, key}, acc), do: [key | acc]
  defp references({:unary, _, ast}, acc), do: references(ast, acc)
  defp references({:binary, _, left, right}, acc), do: references(right, references(left, acc))
  defp references({:call, _, args}, acc), do: Enum.reduce(args, acc, &references/2)
  defp references(_, acc), do: acc
end
