defmodule MontyWeb.ModelLiveTest do
  use MontyWeb.ConnCase

  import Phoenix.LiveViewTest
  import Monty.ModelsFixtures

  alias Monty.{Models, Repo}
  alias Monty.Accounts.Scope

  test "sandbox renders and calculates without an account", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/try")
    assert has_element?(view, "#model-canvas")
    assert has_element?(view, "#metrics button", "Cash in the bank")
    assert has_element?(view, "#metric-statistics")
    assert has_element?(view, "#duplicate-model")
    refute has_element?(view, "#save-model")
    refute has_element?(view, "#model-settings")

    view |> form("#metric-form", metric: %{name: "Savings", input: "100"}) |> render_change()
    assert has_element?(view, "#stat-median", "100.0")
    assert has_element?(view, "#metrics button", "Savings")
    view |> element("#formula-help") |> render_click()
    assert has_element?(view, "#formula-guide")
  end

  test "invalid formulas are visible and do not kill the editor", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/try")
    view |> form("#metric-form", metric: %{input: "=UNKNOWN + 1"}) |> render_change()
    assert has_element?(view, "#metric-error")
    view |> form("#metric-form", metric: %{input: "12 to 24"}) |> render_change()
    refute has_element?(view, "#metric-error")
    assert has_element?(view, "#metric-statistics")
  end

  test "public viewers cannot mutate using forged events", %{conn: conn} do
    owner = scope_fixture()
    model = model_fixture(owner, %{visibility: :public})
    {:ok, view, _} = live(conn, ~p"/models/#{model.id}")
    assert has_element?(view, "#model-page")
    refute has_element?(view, "#add-metric")
    refute has_element?(view, "#save-model")
    assert has_element?(view, "#metric_name[readonly]")
    assert has_element?(view, "#metrics button[draggable=false]")
    render_click(view, "add-metric")
    render_click(view, "delete-metric", %{"id" => hd(model.metrics)["id"]})

    render_submit(view, "save-metric", %{
      "metric" => %{"name" => "Stolen", "input" => "9", "distribution" => "normal"}
    })

    render_click(view, "save")
    assert Repo.reload!(model).metrics == model.metrics
  end

  test "private models and malformed IDs are unavailable to guests", %{conn: conn} do
    model = model_fixture(scope_fixture())
    assert {:error, {:live_redirect, %{to: "/explore"}}} = live(conn, ~p"/models/#{model.id}")
    assert {:error, {:live_redirect, %{to: "/explore"}}} = live(conn, "/models/not-a-uuid")
  end

  describe "owner editor" do
    setup :register_and_log_in_user

    setup %{user: user} do
      scope = Scope.for_user(user)
      %{scope: scope, model: model_fixture(scope)}
    end

    test "previews, saves, and reopens edits with immutable references", %{
      conn: conn,
      model: model
    } do
      {:ok, view, _} = live(conn, ~p"/models/#{model.id}")
      assert has_element?(view, "#save-model")

      view
      |> form("#metric-form", metric: %{name: "Updated assumption", input: "42"})
      |> render_change()

      assert has_element?(view, "#save-status", "Unsaved changes")
      assert Repo.reload!(model).metrics == model.metrics
      view |> element("#save-model") |> render_click()
      assert has_element?(view, "#save-status", "All changes saved")

      assert [%{"name" => "Updated assumption", "input" => "42", "key" => "A"}] =
               Repo.reload!(model).metrics

      {:ok, reopened, _} = live(conn, ~p"/models/#{model.id}")
      assert has_element?(reopened, "#metric_name[value='Updated assumption']")
      assert has_element?(reopened, "#stat-median", "42.0")
    end

    test "adds, moves, undoes, and removes metrics", %{conn: conn, model: model} do
      {:ok, view, _} = live(conn, ~p"/models/#{model.id}")
      assert has_element?(view, "#metrics button[draggable=true][aria-pressed=true]")
      view |> element("#add-metric") |> render_click()
      assert has_element?(view, "#metrics button", "New metric")
      view |> element("#move-down") |> render_click()
      view |> element("#save-model") |> render_click()
      assert [%{"key" => "A"}, %{"key" => "B", "x" => 1, "y" => 1}] = Repo.reload!(model).metrics
      view |> element("#delete-metric") |> render_click()
      refute has_element?(view, "#metrics button", "New metric")
      view |> element("#undo") |> render_click()
      assert has_element?(view, "#metrics button", "New metric")
    end

    test "deleting the last metric can be saved and reopened", %{conn: conn, model: model} do
      {:ok, view, _} = live(conn, ~p"/models/#{model.id}")
      view |> element("#delete-metric") |> render_click()
      assert has_element?(view, "#empty-canvas")
      view |> element("#save-model") |> render_click()
      assert Repo.reload!(model).metrics == []
      {:ok, reopened, _} = live(conn, ~p"/models/#{model.id}")
      assert has_element?(reopened, "#empty-canvas")
      refute has_element?(reopened, "#metric-form")
    end

    test "invalid pending fields cannot produce a false global save", %{conn: conn, model: model} do
      {:ok, view, _} = live(conn, ~p"/models/#{model.id}")
      view |> form("#metric-form", metric: %{name: "", input: "42"}) |> render_change()
      assert has_element?(view, "#save-status", "Unsaved changes")
      assert has_element?(view, "#save-model[disabled]")
      render_click(view, "save")
      assert has_element?(view, "#flash-error", "before saving")
      assert Repo.reload!(model).metrics == model.metrics
      view |> form("#metric-form", metric: %{name: "Valid", input: "42"}) |> render_submit()
      assert hd(Repo.reload!(model).metrics)["input"] == "42"
    end

    test "submitted metric identity survives a selection change", %{conn: conn, scope: scope} do
      a = metric_fixture(%{"name" => "Revenue"})
      b = metric_fixture(%{"name" => "Costs", "key" => "B", "x" => 1})
      model = model_fixture(scope, %{metrics: [a, b]})
      {:ok, view, _} = live(conn, ~p"/models/#{model.id}")
      view |> element("#metrics-#{b["id"]}") |> render_click()
      render_change(view, "edit-metric", %{"metric" => %{"id" => a["id"], "input" => "123"}})
      assert has_element?(view, "#metric_name[value='Costs']")
      view |> element("#save-model") |> render_click()

      assert [
               %{"name" => "Revenue", "input" => "123"},
               %{"name" => "Costs", "input" => "10 to 20"}
             ] = Repo.reload!(model).metrics
    end

    test "deleted references are not silently assigned to newly added metrics", %{
      conn: conn,
      scope: scope
    } do
      a = metric_fixture()
      b = metric_fixture(%{"key" => "B", "input" => "=A * 2", "x" => 1})
      model = model_fixture(scope, %{metrics: [a, b]})
      {:ok, view, _} = live(conn, ~p"/models/#{model.id}")
      view |> element("#delete-metric") |> render_click()
      assert has_element?(view, "#metric-error")
      view |> element("#add-metric") |> render_click()
      view |> element("#save-model") |> render_click()
      assert [%{"key" => "B"}, %{"key" => "C"}] = Repo.reload!(model).metrics
    end

    test "settings control visibility and private models stay out of discovery", %{
      conn: conn,
      model: model
    } do
      {:ok, view, _} = live(conn, ~p"/models/#{model.id}")
      view |> element("#model-settings") |> render_click()

      view
      |> form("#model-settings-form", model: %{title: "Shared forecast", visibility: "unlisted"})
      |> render_submit()

      assert Repo.reload!(model).visibility == :unlisted
      assert Models.list_models(nil, query: "Shared forecast") == []
      assert {:ok, _} = Models.get_model(nil, model.id)
    end

    test "clearing notes removes the previous assumption text", %{conn: conn, scope: scope} do
      metric = metric_fixture(%{"notes" => "An assumption to remove"})
      model = model_fixture(scope, %{metrics: [metric]})
      {:ok, view, _} = live(conn, ~p"/models/#{model.id}")
      view |> form("#metric-form", metric: %{notes: ""}) |> render_submit()
      assert hd(Repo.reload!(model).metrics)["notes"] in [nil, ""]
    end

    test "stale editors cannot overwrite another session", %{
      conn: conn,
      model: model,
      scope: scope
    } do
      {:ok, view, _} = live(conn, ~p"/models/#{model.id}")
      assert {:ok, _} = Models.update_model(scope, model, %{title: "Changed elsewhere"})
      view |> form("#metric-form", metric: %{input: "99"}) |> render_change()
      view |> element("#save-model") |> render_click()
      assert has_element?(view, "#flash-error", "another session")
      assert Repo.reload!(model).title == "Changed elsewhere"
      assert Repo.reload!(model).metrics == model.metrics
      assert has_element?(view, "#save-status", "Unsaved changes")
    end

    test "sandbox copy persists a private owned model", %{conn: conn, user: user} do
      {:ok, view, _} = live(conn, ~p"/try")
      view |> form("#metric-form", metric: %{input: "123"}) |> render_change()
      view |> element("#duplicate-model") |> render_click()
      {path, _flash} = assert_redirect(view)
      id = String.replace_prefix(path, "/models/", "")
      assert {:ok, copy} = Models.get_model(Scope.for_user(user), id)
      assert copy.visibility == :private
      assert hd(copy.metrics)["input"] == "123"
    end

    test "export emits a portable model without account or token data", %{
      conn: conn,
      model: model
    } do
      {:ok, view, _} = live(conn, ~p"/models/#{model.id}")
      view |> element("#export-model") |> render_click()
      assert_push_event(view, "download-model", %{name: "monty-model.json", content: content})
      data = Jason.decode!(content)
      assert data["format"] == "monty"
      assert data["metrics"] == model.metrics
      refute Map.has_key?(data, "user_id")
      refute Map.has_key?(data, "user")
    end
  end
end
