defmodule Monty.Simulation.Beta do
  @moduledoc false

  # Standard beta-PERT (weight 4) needs only shapes in [1, 5].
  # Sample Beta(alpha, beta) as X / (X + Y) for independent unit-scale
  # gamma variables. Marsaglia–Tsang rejection sampling handles these shapes
  # without the additional transformation required for shapes below one.
  @max_attempts 64

  def sample(alpha, beta, state) when alpha >= 1 and alpha <= 5 and beta >= 1 and beta <= 5 do
    with {{:ok, x}, state} <- gamma(alpha, state),
         {{:ok, y}, state} <- gamma(beta, state) do
      {{:ok, x / (x + y)}, state}
    end
  end

  defp gamma(shape, state) do
    d = shape - 1.0 / 3.0
    c = 1.0 / :math.sqrt(9.0 * d)
    gamma_draw(d, c, state, @max_attempts)
  end

  defp gamma_draw(_d, _c, state, 0),
    do: {{:error, "PERT sampler did not converge"}, state}

  defp gamma_draw(d, c, state, attempts) do
    {x, state} = :rand.normal_s(state)
    root = 1.0 + c * x

    if root > 0.0 do
      v = root * root * root
      {u, state} = :rand.uniform_s(state)
      x_squared = x * x

      if u < 1.0 - 0.0331 * x_squared * x_squared or
           :math.log(u) < 0.5 * x_squared + d * (1.0 - v + :math.log(v)) do
        {{:ok, d * v}, state}
      else
        gamma_draw(d, c, state, attempts - 1)
      end
    else
      gamma_draw(d, c, state, attempts - 1)
    end
  end
end
