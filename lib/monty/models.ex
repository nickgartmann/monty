defmodule Monty.Models do
  @moduledoc "Ownership, visibility and full-text catalog operations for estimates."
  import Ecto.Query

  alias Monty.Models.Model
  alias Monty.Repo

  @doc """
  Lists recent public models, or the signed-in owner's models with `owned: true`.
  Public searches use FTS5 before applying the result limit; unlisted models are
  accessible only by direct link. Guests requesting `owned: true` see no models.
  """
  def list_models(scope, opts \\ []) do
    owned? = Keyword.get(opts, :owned, false)
    limit = Keyword.get(opts, :limit, 50)
    limit = if is_integer(limit), do: min(max(limit, 1), 100), else: 50

    query =
      if owned? do
        case owner_id(scope) do
          nil -> from(m in Model, where: false)
          id -> from(m in Model, where: m.user_id == ^id)
        end
      else
        from(m in Model, where: m.visibility == :public)
      end

    query
    |> search(Keyword.get(opts, :query, ""))
    |> order_by([m], desc: m.inserted_at, desc: m.id)
    |> limit(^limit)
    |> preload(:user)
    |> Repo.all()
  end

  @doc "Returns public/unlisted models by link, and private models only to their owner."
  def get_model(scope, id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %Model{} = model <- Repo.get(Model, id),
         true <- readable?(model, scope) do
      {:ok, Repo.preload(model, :user)}
    else
      _ -> {:error, :not_found}
    end
  end

  @doc "Creates a model owned by the signed-in user, ignoring any supplied user_id."
  def create_model(scope, attrs) do
    case owner_id(scope) do
      nil ->
        {:error, :unauthorized}

      user_id ->
        %Model{user_id: user_id}
        |> Model.changeset(attrs)
        |> Repo.insert()
        |> preload_result()
    end
  end

  @doc "Updates an owned persisted model, re-fetching it rather than trusting the passed struct."
  def update_model(scope, %Model{id: id, lock_version: version}, attrs) do
    with {:ok, model} <- owned_model(scope, id) do
      if model.lock_version == version do
        model
        |> Model.changeset(attrs)
        |> Ecto.Changeset.optimistic_lock(:lock_version)
        |> Repo.update()
        |> preload_result()
      else
        {:error, :stale}
      end
    end
  rescue
    Ecto.StaleEntryError -> {:error, :stale}
  end

  def update_model(_scope, _model, _attrs), do: {:error, :unauthorized}

  @doc "Deletes an owned persisted model regardless of its visibility."
  def delete_model(scope, %Model{id: id}) do
    with {:ok, model} <- owned_model(scope, id) do
      Repo.delete(model)
    end
  end

  def delete_model(_scope, _model), do: {:error, :unauthorized}

  def change_model(model, attrs \\ %{}), do: Model.changeset(model, attrs)

  @doc "Copies a readable model into the current user's private workspace."
  def duplicate_model(scope, %Model{id: id}) do
    with user_id when not is_nil(user_id) <- owner_id(scope),
         {:ok, source} <- get_model(scope, id) do
      create_model(scope, %{
        title: source.title,
        description: source.description,
        visibility: :private,
        metrics: Enum.map(source.metrics, &Map.new/1)
      })
    else
      nil -> {:error, :unauthorized}
      error -> error
    end
  end

  def duplicate_model(_scope, _model), do: {:error, :not_found}

  defp owned_model(scope, id) do
    with user_id when not is_nil(user_id) <- owner_id(scope),
         {:ok, id} <- Ecto.UUID.cast(id),
         %Model{} = model <- Repo.get_by(Model, id: id, user_id: user_id) do
      {:ok, model}
    else
      _ -> {:error, :unauthorized}
    end
  end

  defp readable?(model, scope),
    do: model.visibility in [:public, :unlisted] or model.user_id == owner_id(scope)

  defp owner_id(%{user: %{id: id}}) when is_binary(id), do: id
  defp owner_id(_), do: nil

  defp preload_result({:ok, model}), do: {:ok, Repo.preload(model, :user)}
  defp preload_result(error), do: error

  defp search(query, input) when is_binary(input) do
    # Tokenize rather than passing raw user input to the FTS query parser.
    terms =
      input
      |> String.slice(0, 256)
      |> String.downcase()
      |> then(&Regex.scan(~r/[\p{L}\p{N}]+/u, &1))
      |> Enum.take(8)
      |> Enum.map(fn [word] -> ~s("#{word}"*) end)

    case terms do
      [] ->
        query

      _ ->
        match_query = Enum.join(terms, " AND ")

        where(
          query,
          [m],
          fragment(
            "? IN (SELECT id FROM models WHERE rowid IN (SELECT rowid FROM model_search WHERE model_search MATCH ?))",
            m.id,
            ^match_query
          )
        )
    end
  end

  defp search(query, _), do: query
end
