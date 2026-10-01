defmodule Monty.Simulation do
  @moduledoc """
  A bounded, process-local Monte Carlo engine for spreadsheet metrics.

  `run/2` accepts up to 100 maps with unique `key` identifiers (`[A-Za-z_][A-Za-z0-9_]*`)
  and `input` text. Map keys may be atoms or strings. `id` and `name` are ignored by
  the engine. Bare inputs are signed numbers (commas and `%` allowed) or
  `lower to upper`; formulas must start with `=`. Formulas support references,
  parentheses, unary signs, `+ - * / ^` (power is right-associative), and
  `min`, `max`, `abs`, `sqrt`, `log` (natural log), `exp`, `mean`, `sum`.
  Percentages are fractions (`25%` is `0.25`).

  An interval is the 5th–95th percentile of a normal distribution by default.
  `"lognormal"` interprets positive endpoints as its 5th–95th percentiles;
  `"uniform"` uses the endpoints as its full bounds. A distribution is only
  meaningful for intervals. Results contain sample-aligned vectors, arithmetic
  mean, median, empirical 5th/95th percentiles, and a 20-bin histogram spanning
  the observed minimum and maximum (constant values occupy the center bin).
  Direct dependencies are returned in first-appearance order.

  `:samples` defaults to 1_000 and must be 1..10_000. An integer or three-integer
  tuple `:seed` makes draws deterministic without modifying the calling process's RNG.
  Invalid metrics and their dependents produce per-key errors, rather than
  interrupting independent metrics. Invalid run-level options or more than
  100 metrics return `%{"_error" => %{error: ..., dependencies: []}}`.
  Missing or invalid keys receive a reserved `#metric_N` result key.
  """

  alias Monty.Simulation.Parser

  @max_metrics 100
  @max_samples 10_000
  @z90 1.6448536269514722
  @max_float 1.7976931348623157e308
  @key ~r/\A[A-Za-z_][A-Za-z0-9_]*\z/

  @spec run([map()], keyword()) :: map()
  def run(metrics, opts \\ [])

  def run(metrics, opts) when is_list(metrics) and is_list(opts) do
    cond do
      length(Enum.take(metrics, @max_metrics + 1)) > @max_metrics ->
        global_error("At most #{@max_metrics} metrics are allowed")

      not Keyword.keyword?(opts) ->
        global_error("Options must be a keyword list")

      true ->
        samples = Keyword.get(opts, :samples, 1_000)
        seed = Keyword.get(opts, :seed, :erlang.unique_integer([:positive]))

        cond do
          not (is_integer(samples) and samples in 1..@max_samples) ->
            global_error("Samples must be between 1 and #{@max_samples}")

          not valid_seed?(seed) ->
            global_error("Seed must be an integer or a three-integer tuple")

          true ->
            {order, nodes} = prepare(metrics)
            state = :rand.seed_s(:exsss, seed_tuple(seed))

            {results, _state} =
              Enum.reduce(order, {%{}, state}, fn key, {results, state} ->
                {_, results, state} = calculate(key, nodes, results, state, samples, [])
                {results, state}
              end)

            results
        end
    end
  end

  def run(_, _), do: global_error("Metrics must be a list and options a keyword list")

  defp valid_seed?(seed) when is_integer(seed), do: true
  defp valid_seed?({a, b, c}), do: is_integer(a) and is_integer(b) and is_integer(c)
  defp valid_seed?(_), do: false

  defp seed_tuple(seed) do
    {
      :erlang.phash2({seed, 1}, 4_294_967_295) + 1,
      :erlang.phash2({seed, 2}, 4_294_967_295) + 1,
      :erlang.phash2({seed, 3}, 4_294_967_295) + 1
    }
  end

  defp global_error(message), do: %{"_error" => %{error: message, dependencies: []}}

  defp prepare(metrics) do
    indexed =
      metrics
      |> Enum.with_index(1)
      |> Enum.map(fn {metric, index} ->
        raw_key = if is_map(metric), do: field(metric, :key), else: nil
        key = if is_binary(raw_key) and raw_key != "", do: raw_key, else: "#metric_#{index}"
        {key, metric}
      end)

    counts = Enum.frequencies_by(indexed, &elem(&1, 0))

    nodes =
      Map.new(indexed, fn {key, metric} ->
        parsed =
          cond do
            counts[key] > 1 -> {:error, "Duplicate metric key: #{key}"}
            not Regex.match?(@key, key) -> {:error, "Invalid metric key: #{key}"}
            not is_map(metric) -> {:error, "Metric must be a map"}
            true -> parse_metric(metric)
          end

        {key, parsed}
      end)

    {Enum.map(indexed, &elem(&1, 0)), nodes}
  end

  defp field(metric, key), do: Map.get(metric, key, Map.get(metric, Atom.to_string(key)))

  defp parse_metric(metric) do
    input = field(metric, :input)
    distribution = field(metric, :distribution) || "normal"

    with {:ok, definition, dependencies} <- Parser.parse(input),
         {:ok, distribution} <- distribution(distribution),
         :ok <- valid_definition(definition, distribution) do
      %{definition: definition, distribution: distribution, dependencies: dependencies}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp distribution(value) when value in ["normal", :normal], do: {:ok, :normal}
  defp distribution(value) when value in ["lognormal", :lognormal], do: {:ok, :lognormal}
  defp distribution(value) when value in ["uniform", :uniform], do: {:ok, :uniform}
  defp distribution(_), do: {:error, "Unknown distribution"}

  defp valid_definition({:interval, low, high}, distribution) do
    cond do
      low >= high -> {:error, "Range lower bound must be less than upper bound"}
      distribution == :lognormal and low <= 0.0 -> {:error, "Lognormal bounds must be positive"}
      true -> :ok
    end
  end

  defp valid_definition(_, _), do: :ok

  defp calculate(key, nodes, results, state, count, visiting) do
    cond do
      Map.has_key?(results, key) ->
        {Map.fetch!(results, key), results, state}

      key in visiting ->
        cycle = Enum.drop(visiting, Enum.find_index(visiting, &(&1 == key))) ++ [key]

        {%{error: "Cyclic reference: #{Enum.join(cycle, " -> ")}", dependencies: []}, results,
         state}

      not Map.has_key?(nodes, key) ->
        {%{error: "Unknown reference: #{key}", dependencies: []}, results, state}

      true ->
        node = Map.fetch!(nodes, key)

        {result, results, state} =
          case node do
            {:error, reason} ->
              {%{error: reason, dependencies: []}, results, state}

            %{dependencies: dependencies} ->
              resolve(node, dependencies, key, nodes, results, state, count, visiting ++ [key])
          end

        {result, Map.put(results, key, result), state}
    end
  end

  defp resolve(node, dependencies, key, nodes, results, state, count, visiting) do
    {problem, results, state} =
      Enum.reduce_while(dependencies, {nil, results, state}, fn dependency, {_, results, state} ->
        {result, results, state} = calculate(dependency, nodes, results, state, count, visiting)

        case result do
          %{error: reason} ->
            {:halt, {"Dependency #{dependency}: #{reason}", results, state}}

          _ ->
            {:cont, {nil, results, state}}
        end
      end)

    if problem do
      {%{error: problem, dependencies: dependencies}, results, state}
    else
      vectors =
        Map.new(dependencies, fn dependency ->
          {dependency,
           results |> Map.fetch!(dependency) |> Map.fetch!(:samples) |> List.to_tuple()}
        end)

      case sample(node, vectors, count, state) do
        {:ok, samples, state} ->
          result =
            try do
              summary(samples, dependencies)
            rescue
              ArithmeticError ->
                %{error: "Non-finite or overflow result", dependencies: dependencies}
            end

          {result, results, state}

        {:error, reason, state} ->
          {%{error: "#{key}: #{reason}", dependencies: dependencies}, results, state}
      end
    end
  end

  defp sample(%{definition: {:constant, number}}, _, count, state),
    do: {:ok, List.duplicate(number, count), state}

  defp sample(%{definition: {:interval, low, high}, distribution: distribution}, _, count, state) do
    normal_parameters =
      if distribution == :lognormal do
        a = :math.log(low)
        b = :math.log(high)
        {(a + b) / 2.0, (b - a) / (2.0 * @z90)}
      else
        {low / 2.0 + high / 2.0, (high / 2.0 - low / 2.0) / @z90}
      end

    draw(count, state, fn state ->
      case distribution do
        :uniform ->
          {u, state} = :rand.uniform_s(state)
          {safe_math(fn -> low * (1.0 - u) + high * u end), state}

        :normal ->
          {z, state} = :rand.normal_s(state)
          {mu, sigma} = normal_parameters
          {safe_math(fn -> mu + sigma * z end), state}

        :lognormal ->
          {z, state} = :rand.normal_s(state)
          {mu, sigma} = normal_parameters
          {safe_math(fn -> :math.exp(mu + sigma * z) end), state}
      end
    end)
  end

  defp sample(%{definition: {:formula, ast}}, vectors, count, state) do
    case draw(count, 0, fn state_index ->
           # Formulas make no random draws; use the index instead of RNG state here.
           {evaluate(ast, vectors, state_index), state_index + 1}
         end) do
      {:ok, values, _index} -> {:ok, values, state}
      {:error, reason, _index} -> {:error, reason, state}
    end
  end

  defp draw(count, initial, fun) do
    Enum.reduce_while(1..count, {[], initial}, fn _, {values, cursor} ->
      {value, cursor} = fun.(cursor)

      case value do
        {:ok, number} -> {:cont, {[number | values], cursor}}
        {:error, reason} -> {:halt, {:error, reason, cursor}}
      end
    end)
    |> case do
      {:error, reason, cursor} -> {:error, reason, cursor}
      {values, cursor} -> {:ok, Enum.reverse(values), cursor}
    end
  end

  defp evaluate({:number, number}, _, _), do: {:ok, number}
  defp evaluate({:ref, key}, vectors, index), do: {:ok, elem(Map.fetch!(vectors, key), index)}

  defp evaluate({:unary, op, ast}, vectors, index) do
    with {:ok, number} <- evaluate(ast, vectors, index) do
      finite(if(op == :subtract, do: -number, else: number))
    end
  end

  defp evaluate({:binary, op, left, right}, vectors, index) do
    with {:ok, a} <- evaluate(left, vectors, index),
         {:ok, b} <- evaluate(right, vectors, index) do
      safe_math(fn ->
        case op do
          :add -> a + b
          :subtract -> a - b
          :multiply -> a * b
          :divide when b == 0.0 -> throw(:division_by_zero)
          :divide -> a / b
          :power -> :math.pow(a, b)
        end
      end)
    end
  catch
    :division_by_zero -> {:error, "Division by zero"}
  end

  defp evaluate({:call, function, args}, vectors, index) do
    with {:ok, values} <- evaluate_args(args, vectors, index) do
      safe_math(fn ->
        case {function, values} do
          {:abs, [value]} ->
            abs(value)

          {:sqrt, [value]} ->
            :math.sqrt(value)

          {:log, [value]} ->
            :math.log(value)

          {:exp, [value]} ->
            :math.exp(value)

          {:sum, values} ->
            Enum.reduce(values, 0.0, &+/2)

          {:mean, values} ->
            count = length(values)
            Enum.reduce(values, 0.0, fn value, sum -> sum + value / count end)

          {:min, values} ->
            Enum.min(values)

          {:max, values} ->
            Enum.max(values)
        end
      end)
    end
  end

  defp evaluate_args(args, vectors, index) do
    Enum.reduce_while(args, {:ok, []}, fn ast, {:ok, values} ->
      case evaluate(ast, vectors, index) do
        {:ok, value} -> {:cont, {:ok, [value | values]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, reversed} -> {:ok, Enum.reverse(reversed)}
      error -> error
    end
  end

  defp safe_math(fun) do
    try do
      finite(fun.())
    rescue
      ArithmeticError -> {:error, "Non-finite or invalid arithmetic"}
      ArgumentError -> {:error, "Non-finite or invalid arithmetic"}
    end
  end

  defp finite(value) when is_number(value) and value <= @max_float and value >= -@max_float,
    do: {:ok, value * 1.0}

  defp finite(_), do: {:error, "Non-finite or overflow result"}

  defp summary(samples, dependencies) do
    sorted = Enum.sort(samples)
    count = length(samples)
    minimum = hd(sorted)
    maximum = List.last(sorted)
    histogram = histogram(samples, minimum, maximum)

    %{
      mean: Enum.reduce(samples, 0.0, fn value, sum -> sum + value / count end),
      median: percentile(sorted, 0.5),
      low: percentile(sorted, 0.05),
      high: percentile(sorted, 0.95),
      histogram: histogram,
      samples: samples,
      dependencies: dependencies
    }
  end

  defp percentile(sorted, probability) do
    position = (length(sorted) - 1) * probability
    lower = trunc(position)
    weight = position - lower
    a = Enum.at(sorted, lower)
    b = Enum.at(sorted, min(lower + 1, length(sorted) - 1))
    a * (1.0 - weight) + b * weight
  end

  defp histogram(samples, minimum, maximum) do
    counts =
      Enum.reduce(samples, %{}, fn value, counts ->
        bin =
          if minimum == maximum do
            10
          else
            # Halve only when subtracting opposite extreme signs could overflow.
            fraction =
              if minimum < 0.0 and maximum > 0.0 and
                   (minimum < -@max_float / 2 or maximum > @max_float / 2) do
                (value / 2.0 - minimum / 2.0) / (maximum / 2.0 - minimum / 2.0)
              else
                (value - minimum) / (maximum - minimum)
              end

            min(19, max(0, trunc(fraction * 20)))
          end

        Map.update(counts, bin, 1, &(&1 + 1))
      end)

    Enum.map(0..19, &Map.get(counts, &1, 0))
  end
end
