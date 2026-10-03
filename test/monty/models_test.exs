defmodule Monty.ModelsTest do
  use Monty.DataCase

  alias Monty.Models
  alias Monty.Models.Model
  alias Monty.Repo
  import Monty.ModelsFixtures

  setup do
    %{owner: scope_fixture(), other: scope_fixture()}
  end

  describe "visibility and ownership" do
    test "catalog includes only public models; owned lists are isolated and preloaded", %{
      owner: owner,
      other: other
    } do
      public = model_fixture(owner, %{visibility: :public})
      private = model_fixture(owner)
      unlisted = model_fixture(owner, %{visibility: :unlisted})
      _other = model_fixture(other, %{visibility: :public})

      assert Enum.map(Models.list_models(nil), & &1.id) |> Enum.sort() ==
               Enum.map(Models.list_models(owner), & &1.id) |> Enum.sort()

      assert Enum.sort(Enum.map(Models.list_models(owner, owned: true), & &1.id)) ==
               Enum.sort([public.id, private.id, unlisted.id])

      assert Models.list_models(nil, owned: true) == []
      assert Enum.all?(Models.list_models(owner), &Ecto.assoc_loaded?(&1.user))
      assert Enum.map(Models.list_models(nil, limit: 1), & &1.id) |> length() == 1
    end

    test "unlisted links work but private links do not leak", %{owner: owner, other: other} do
      unlisted = model_fixture(owner, %{visibility: :unlisted})
      private = model_fixture(owner)

      assert {:ok, %Model{}} = Models.get_model(nil, unlisted.id)
      assert {:ok, %Model{}} = Models.get_model(other, unlisted.id)
      assert {:ok, %Model{}} = Models.get_model(owner, private.id)
      assert {:error, :not_found} = Models.get_model(other, private.id)
      assert {:error, :not_found} = Models.get_model(nil, private.id)
      assert {:error, :not_found} = Models.get_model(nil, "not-a-uuid")
      refute unlisted.id in Enum.map(Models.list_models(nil), & &1.id)
    end

    test "guests cannot write and user_id cannot be forged", %{owner: owner, other: other} do
      assert {:error, :unauthorized} = Models.create_model(nil, %{title: "Guest"})
      model = model_fixture(owner, %{user_id: other.user.id})
      assert model.user_id == owner.user.id
      assert {:error, :unauthorized} = Models.update_model(nil, model, %{title: "Guest"})
      assert {:error, :unauthorized} = Models.delete_model(nil, model)
    end

    test "re-fetches records to reject forged structs on updates and deletes", %{
      owner: owner,
      other: other
    } do
      for visibility <- [:public, :unlisted, :private] do
        model = model_fixture(owner, %{visibility: visibility})
        forged = %{model | user_id: other.user.id}
        assert {:error, :unauthorized} = Models.update_model(other, forged, %{title: "Stolen"})
        assert {:error, :unauthorized} = Models.delete_model(other, forged)

        assert {:ok, updated} =
                 Models.update_model(owner, forged, %{title: "New", user_id: other.user.id})

        assert updated.user_id == owner.user.id
        assert {:ok, _} = Models.delete_model(owner, forged)
        assert {:error, :not_found} = Models.get_model(owner, model.id)
      end
    end

    test "stale updates do not overwrite an editor's newer changes", %{owner: owner} do
      old = model_fixture(owner)
      assert {:ok, updated} = Models.update_model(owner, old, %{title: "From first editor"})
      assert updated.lock_version == old.lock_version + 1
      assert {:error, :stale} = Models.update_model(owner, old, %{title: "From stale editor"})
      assert {:ok, persisted} = Models.get_model(owner, old.id)
      assert persisted.title == "From first editor"
    end

    test "duplicates readable models into a private copy, without sharing metric maps", %{
      owner: owner,
      other: other
    } do
      source = model_fixture(owner, %{visibility: :unlisted})
      assert {:ok, copy} = Models.duplicate_model(other, source)
      assert copy.id != source.id
      assert copy.user_id == other.user.id
      assert copy.visibility == :private
      assert copy.metrics == source.metrics
      assert {:error, :unauthorized} = Models.duplicate_model(nil, source)
      assert {:error, :not_found} = Models.duplicate_model(other, model_fixture(owner))
    end
  end

  describe "FTS catalog" do
    test "searches title and description before limit, with quoted prefix terms", %{owner: owner} do
      model_fixture(owner, %{title: "Recent irrelevant", visibility: :public})
      title_match = model_fixture(owner, %{title: "Forecasting revenue", visibility: :public})

      description_match =
        model_fixture(owner, %{
          title: "Other",
          description: "Revenue forecast",
          visibility: :public
        })

      model_fixture(owner, %{title: "Forecasting revenue", visibility: :unlisted})
      model_fixture(owner, %{title: "Forecasting revenue"})

      assert [limited] = Models.list_models(nil, query: "fore rev", limit: 1)
      assert limited.id in [title_match.id, description_match.id]

      assert Enum.sort(Enum.map(Models.list_models(nil, query: "revenue"), & &1.id)) ==
               Enum.sort([title_match.id, description_match.id])

      assert Models.list_models(owner, query: "revenue", owned: true) |> length() == 4
      assert Models.list_models(nil, query: "revenue", owned: true) == []
    end

    test "triggers synchronize updates and deletions", %{owner: owner} do
      model = model_fixture(owner, %{title: "Originalkeyword", visibility: :public})
      assert [model] == Models.list_models(nil, query: "originalkey")

      assert {:ok, updated} =
               Models.update_model(owner, model, %{
                 title: "Replacementword",
                 description: "Freshterm"
               })

      assert Models.list_models(nil, query: "originalkey") == []
      assert [updated] == Models.list_models(nil, query: "replacement")
      assert [updated] == Models.list_models(nil, query: "freshterm")
      assert {:ok, _} = Models.delete_model(owner, updated)
      assert Models.list_models(nil, query: "replacement") == []
    end

    test "punctuation, operators and very long searches cannot break MATCH", %{owner: owner} do
      model_fixture(owner, %{title: "Revenue", visibility: :public})
      assert is_list(Models.list_models(nil, query: ~s("revenue" OR "nope")))
      assert Models.list_models(nil, query: ~s(!!!"^:*)) |> is_list()
      assert Models.list_models(nil, query: String.duplicate("(", 10_000)) |> is_list()
      assert Models.list_models(nil, query: String.duplicate("x", 10_000)) == []
    end
  end

  describe "metric validation" do
    test "accepts the metric contract and rejects malformed or duplicate metrics",
         %{
           owner: owner
         } do
      base = metric_fixture()
      second = metric_fixture(%{"key" => "B", "x" => 1, "input" => "=A * 2"})
      model = model_fixture(owner, %{metrics: [base, second]})
      assert model.metrics == [base, second]

      invalid = [
        [%{"key" => "A"}],
        [Map.put(base, "id", "invalid")],
        [Map.put(base, "key", "lowercase")],
        [Map.put(base, "distribution", "triangular")],
        [Map.put(base, "input", String.duplicate("x", 1_001))],
        [Map.put(base, "notes", String.duplicate("n", 2_001))],
        [Map.put(base, "x", "201")],
        [Map.put(base, "y", 1.5)],
        [Map.put(base, "x", 9_007_199_254_740_992)],
        [Map.put(base, "y", -9_007_199_254_740_992)],
        [Map.delete(base, "x")],
        [base, Map.put(second, "key", "A")],
        [base, Map.put(second, "x", 0) |> Map.put("y", 0)],
        [base, Map.put(second, "id", base["id"])],
        Enum.map(1..101, fn i -> metric_fixture(%{"key" => "A", "x" => rem(i, 12), "y" => i}) end)
      ]

      for metrics <- invalid do
        assert {:error, changeset} =
                 Models.create_model(owner, %{title: "Invalid", metrics: metrics})

        assert errors_on(changeset).metrics
      end
    end

    test "signed coordinates beyond the former limits persist on create and update", %{
      owner: owner
    } do
      base = metric_fixture(%{"x" => -201, "y" => 1201})
      nearby = metric_fixture(%{"key" => "B", "x" => -202, "y" => 1201})

      assert {:ok, model} =
               Models.create_model(owner, %{title: "Fine grid", metrics: [base, nearby]})

      assert model.metrics == [base, nearby]

      moved = Map.merge(base, %{"x" => 201, "y" => -1201})
      assert {:ok, updated} = Models.update_model(owner, model, %{metrics: [moved, nearby]})
      assert updated.metrics == [moved, nearby]
    end

    test "title and description are bounded", %{owner: owner} do
      for attrs <- [
            %{title: ""},
            %{title: String.duplicate("t", 121)},
            %{title: "Valid", description: String.duplicate("d", 4_001)}
          ] do
        assert {:error, _changeset} = Models.create_model(owner, attrs)
      end
    end
  end

  test "migration preserves metric order and fields and invalidates older editor versions", %{
    owner: owner
  } do
    migration = Monty.Repo.Migrations.ConvertMetricPositionsToFineGrid

    unless Code.ensure_loaded?(migration) do
      Code.require_file(
        "../../priv/repo/migrations/20261001200453_convert_metric_positions_to_fine_grid.exs",
        __DIR__
      )
    end

    legacy = [
      metric_fixture(%{"x" => 2, "y" => 1, "extra" => %{"keep" => true}}),
      metric_fixture(%{"key" => "B", "x" => 11, "y" => 99})
    ]

    model = model_fixture(owner)
    empty = model_fixture(owner, %{metrics: []})

    Ecto.Adapters.SQL.query!(
      Repo,
      "UPDATE models SET metrics = ?, lock_version = 5 WHERE id = ?",
      [Jason.encode!(legacy), model.id]
    )

    Ecto.Adapters.SQL.query!(
      Repo,
      apply(migration, :conversion_sql, []),
      []
    )

    converted = Repo.get!(Model, model.id)

    assert converted.metrics ==
             [
               legacy |> Enum.at(0) |> Map.put("x", 28) |> Map.put("y", 11),
               legacy |> Enum.at(1) |> Map.put("x", 154) |> Map.put("y", 1109)
             ]

    assert converted.lock_version == 6
    assert Repo.get!(Model, empty.id).metrics == []
    assert Repo.get!(Model, empty.id).lock_version == empty.lock_version
    assert {:error, :stale} = Models.update_model(owner, model, %{title: "Stale socket"})
  end
end
