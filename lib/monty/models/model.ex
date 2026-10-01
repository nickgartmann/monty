defmodule Monty.Models.Model do
  @moduledoc "A user-owned estimate with JSON-backed grid metrics."
  use Ecto.Schema
  import Ecto.Changeset
  alias Monty.Canvas

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "models" do
    belongs_to :user, Monty.Accounts.User
    field :title, :string
    field :description, :string
    field :visibility, Ecto.Enum, values: [:public, :unlisted, :private], default: :private
    field :metrics, {:array, :map}, default: []
    field :lock_version, :integer, default: 1

    timestamps(type: :utc_datetime)
  end

  @doc "Validates a model; the owner is deliberately never cast from attributes."
  def changeset(model, attrs) do
    model
    |> cast(attrs, [:title, :description, :visibility, :metrics])
    |> update_change(:title, &String.trim/1)
    |> validate_required([:title, :visibility, :metrics])
    |> validate_length(:title, min: 1, max: 120)
    |> validate_length(:description, max: 4_000)
    |> validate_metrics()
    |> foreign_key_constraint(:user_id)
  end

  defp validate_metrics(changeset) do
    case get_field(changeset, :metrics) do
      metrics when is_list(metrics) and length(metrics) <= 100 ->
        errors = Enum.flat_map(metrics, &metric_errors/1)

        keys = Enum.map(metrics, &metric_value(&1, "key"))
        ids = Enum.map(metrics, &metric_value(&1, "id"))
        positions = Enum.map(metrics, &{metric_value(&1, "x"), metric_value(&1, "y")})

        errors = if unique?(keys), do: errors, else: ["metric keys must be unique" | errors]
        errors = if unique?(ids), do: errors, else: ["metric IDs must be unique" | errors]

        errors =
          if unique?(positions), do: errors, else: ["metric positions must be unique" | errors]

        Enum.reduce(errors, changeset, &add_error(&2, :metrics, &1))

      metrics when is_list(metrics) ->
        add_error(changeset, :metrics, "must have at most 100 metrics")

      _ ->
        changeset
    end
  end

  defp unique?(items), do: length(items) == length(Enum.uniq(items))

  defp metric_value(metric, key) when is_map(metric), do: Map.get(metric, key)
  defp metric_value(_metric, _key), do: nil

  defp metric_errors(metric) when is_map(metric) do
    allowed = ~w(id key name input distribution notes x y)
    keys = Map.keys(metric)

    []
    |> maybe_error(Enum.any?(keys, &(&1 not in allowed)), "contains unsupported fields")
    |> maybe_error(not valid_uuid?(metric["id"]), "id must be a UUID")
    |> maybe_error(
      not valid_text?(metric["key"], 1, 4, ~r/\A[A-Z]+\z/),
      "key must be 1–4 uppercase letters"
    )
    |> maybe_error(
      not valid_text?(metric["name"], 1, 120),
      "name is required (max 120 characters)"
    )
    |> maybe_error(
      not valid_text?(metric["input"], 1, 1_000),
      "input is required (max 1000 characters)"
    )
    |> maybe_error(
      metric["distribution"] not in ~w(normal lognormal uniform),
      "invalid distribution"
    )
    |> maybe_error(
      not (is_nil(metric["notes"]) or valid_text?(metric["notes"], 0, 2_000)),
      "notes are too long"
    )
    |> maybe_error(
      not (is_integer(metric["x"]) and metric["x"] in 0..Canvas.max_x()),
      "x must be between 0 and #{Canvas.max_x()}"
    )
    |> maybe_error(
      not (is_integer(metric["y"]) and metric["y"] in 0..Canvas.max_y()),
      "y must be between 0 and #{Canvas.max_y()}"
    )
  end

  defp metric_errors(_), do: ["each metric must be a map"]

  defp valid_uuid?(id) when is_binary(id), do: match?({:ok, _}, Ecto.UUID.cast(id))
  defp valid_uuid?(_), do: false

  defp valid_text?(text, min, max, pattern \\ ~r/\A.*\z/su) do
    is_binary(text) and String.length(text) in min..max and Regex.match?(pattern, text) and
      (min == 0 or String.trim(text) != "")
  end

  defp maybe_error(errors, true, message), do: [message | errors]
  defp maybe_error(errors, false, _message), do: errors
end
