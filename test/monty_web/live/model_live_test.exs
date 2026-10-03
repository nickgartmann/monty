defmodule MontyWeb.ModelLiveTest do
  use MontyWeb.ConnCase

  import Phoenix.LiveViewTest
  import Monty.ModelsFixtures

  alias Monty.{Canvas, Examples, Models, Repo}
  alias Monty.Accounts.Scope

  test "sandbox renders and calculates without an account", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/try")
    assert has_element?(view, "#model-canvas")
    assert has_element?(view, "#canvas-viewport[style*='--metric-height: 120px;']")
    assert has_element?(view, "#metrics #metric_name[value='Cash in the bank']")
    assert has_element?(view, "#metrics [data-metric-summary]", "450.0k")
    assert has_element?(view, "#metrics #metric_input[value='450000']")
    refute has_element?(view, "#metrics button span", "mean")
    refute has_element?(view, "#metric-detail")
    refute has_element?(view, "#metric-statistics")
    assert has_element?(view, "#duplicate-model")
    refute has_element?(view, "#save-model")
    refute has_element?(view, "#model-settings")

    view |> form("#metric-form", metric: %{name: "Savings", input: "100"}) |> render_change()
    assert has_element?(view, "#metrics [data-metric-summary]", "100.0")
    assert has_element?(view, "#metrics #metric_name[value='Savings']")
    view |> element("#formula-help") |> render_click()
    assert has_element?(view, "#formula-guide")
  end

  test "floating model controls collapse to the title and restore their content", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/try")
    assert has_element?(view, ".model-workspace > #model-controls[data-canvas-controls]")
    refute has_element?(view, "#canvas-viewport #model-controls")
    assert has_element?(view, "#model-controls #model-title")
    assert has_element?(view, "#model-controls #model-description")
    assert has_element?(view, "#model-controls #export-model")
    assert has_element?(view, "#model-controls #duplicate-model")
    assert has_element?(view, "#model-controls #model-toolbar #add-metric")
    assert has_element?(view, "#model-controls #model-toolbar #undo")
    refute has_element?(view, "#model-controls-body #model-toolbar")
    refute has_element?(view, "#resample")
    refute has_element?(view, "#model-controls a")

    assert has_element?(
             view,
             "#model-toolbar #formula-help.canvas-tool-button[aria-label='Guide']"
           )

    view |> element("#toggle-model-controls[aria-expanded=true]") |> render_click()
    assert has_element?(view, "#toggle-model-controls[aria-expanded=false]")
    assert has_element?(view, "#model-controls-body[hidden]")
    assert has_element?(view, "#model-controls > div #model-title")
    assert has_element?(view, "#model-canvas #metrics")

    # Canvas edits do not expand the panel.
    view |> form("#metric-form", metric: %{name: "Savings"}) |> render_change()
    assert has_element?(view, "#model-controls-body[hidden]")
    view |> element("#toggle-model-controls") |> render_click()
    assert has_element?(view, "#toggle-model-controls[aria-expanded=true]")
    refute has_element?(view, "#model-controls-body[hidden]")
    assert has_element?(view, "#metric_name[value='Savings']")
  end

  test "external metric tools work while the model card is collapsed", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/try")
    view |> element("#toggle-model-controls") |> render_click()
    assert has_element?(view, "#model-toolbar #add-metric[aria-label='Add metric']")
    assert has_element?(view, "#model-toolbar #undo[disabled]")

    view |> element("#add-metric") |> render_click()
    assert has_element?(view, "#metric_name[value='New metric']")
    assert has_element?(view, "#model-controls-body[hidden]")
    refute has_element?(view, "#undo[disabled]")
    view |> element("#undo") |> render_click()
    refute has_element?(view, "#metric_name[value='New metric']")
    assert has_element?(view, "#model-controls-body[hidden]")
    assert has_element?(view, "#undo[disabled]")
  end

  test "Guide opens a modal without expanding a collapsed metadata card", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/try")
    view |> element("#toggle-model-controls") |> render_click()
    view |> element("#model-toolbar #formula-help[aria-expanded=false]") |> render_click()
    assert has_element?(view, "#model-controls-body[hidden]")
    assert has_element?(view, "#formula-guide #guide-dialog[role=dialog][aria-modal=true]")
    refute has_element?(view, "#model-controls #formula-guide")
    assert has_element?(view, "#formula-help[aria-expanded=true]")

    view |> element("#close-guide") |> render_click()
    refute has_element?(view, "#formula-guide")
    assert has_element?(view, "#model-controls-body[hidden]")
    assert has_element?(view, "#formula-help[aria-expanded=false]")

    view |> element("#toggle-model-controls") |> render_click()
    view |> element("#formula-help[aria-haspopup=dialog]") |> render_click()
    refute has_element?(view, "#model-controls-body[hidden]")
    assert has_element?(view, "#formula-guide")

    view |> element("#formula-guide") |> render_keydown(%{"key" => "Escape"})
    refute has_element?(view, "#formula-guide")
    refute has_element?(view, "#model-controls-body[hidden]")
    assert has_element?(view, "#formula-help[aria-expanded=false]")
  end

  test "invalid formulas are visible and do not kill the editor", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/try")
    view |> form("#metric-form", metric: %{input: "=UNKNOWN + 1"}) |> render_change()
    assert has_element?(view, "#metrics > [data-selected=true] #metric-error")
    view |> form("#metric-form", metric: %{input: "12 to 24"}) |> render_change()
    refute has_element?(view, "#metric-error")
    assert has_element?(view, "#metrics [data-metric-summary]")
  end

  test "public viewers cannot mutate using forged events", %{conn: conn} do
    owner = scope_fixture()
    model = model_fixture(owner, %{visibility: :public})
    {:ok, view, _} = live(conn, ~p"/models/#{model.id}")
    assert has_element?(view, "#model-page")
    refute has_element?(view, "#add-metric")
    refute has_element?(view, "#undo")
    assert has_element?(view, "#model-toolbar #formula-help")
    view |> element("#formula-help") |> render_click()
    assert has_element?(view, "#guide-dialog[role=dialog]")
    view |> element("#close-guide") |> render_click()
    refute has_element?(view, "#save-model")
    refute has_element?(view, "#metrics .metric-delete-button")
    assert has_element?(view, "#metric_name[readonly]")
    assert has_element?(view, "#metrics > [draggable=false]")
    assert has_element?(view, "#metrics > [data-movable=false]")
    assert has_element?(view, "#model-canvas[data-editable=false]")
    render_click(view, "add-metric")
    render_click(view, "add-metric", %{"x" => 10, "y" => 12})
    render_click(view, "delete-metric", %{"id" => hd(model.metrics)["id"]})
    render_click(view, "move-metric", %{"id" => hd(model.metrics)["id"], "x" => 5, "y" => 6})

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

    test "collapsing the controls preserves the settings form", %{conn: conn, model: model} do
      {:ok, view, _} = live(conn, ~p"/models/#{model.id}")
      view |> element("#model-controls #model-settings") |> render_click()
      assert has_element?(view, "#model-controls #model-settings-form")
      view |> element("#toggle-model-controls") |> render_click()
      assert has_element?(view, "#model-controls-body[hidden]")
      view |> element("#toggle-model-controls") |> render_click()
      assert has_element?(view, "#model-controls #model-settings-form")

      view
      |> form("#model-settings-form", model: %{title: "Updated model title"})
      |> render_submit()

      assert has_element?(view, "#model-controls #model-title", "Updated model title")
      assert Repo.reload!(model).title == "Updated model title"
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
      assert has_element?(reopened, "#metrics [data-metric-summary]", "42.0")
    end

    test "distribution formulas preview, save, reopen, and recover from invalid parameters", %{
      conn: conn,
      model: model
    } do
      {:ok, view, _} = live(conn, ~p"/models/#{model.id}")
      view |> element("#formula-help") |> render_click()
      assert has_element?(view, "#distribution-guide")
      refute has_element?(view, "#range-distribution-help")

      view
      |> form("#metric-form", metric: %{input: "=normal(42, 0)"})
      |> render_submit()

      refute has_element?(view, "#metric-error")
      assert has_element?(view, "#metrics [data-metric-summary]", "42.0")
      assert hd(Repo.reload!(model).metrics)["input"] == "=normal(42, 0)"

      {:ok, reopened, _} = live(conn, ~p"/models/#{model.id}")
      assert has_element?(reopened, "#metric_input[value='=normal(42, 0)']")
      assert has_element?(reopened, "#metrics [data-metric-summary]", "42.0")
      reopened |> form("#metric-form", metric: %{input: "=uniform(20, 10)"}) |> render_change()
      assert has_element?(reopened, "#metric-error")
      reopened |> form("#metric-form", metric: %{input: "=uniform(10, 20)"}) |> render_change()
      refute has_element?(reopened, "#metric-error")
      assert has_element?(reopened, "#metrics [data-metric-summary]")
    end

    test "adds, moves, undoes, and removes metrics", %{conn: conn, model: model} do
      {:ok, view, _} = live(conn, ~p"/models/#{model.id}")

      assert has_element?(
               view,
               "#metrics > [data-movable=true][draggable=false][data-selected=true]"
             )

      view |> element("#add-metric") |> render_click()
      assert has_element?(view, "#metric_name[value='New metric']")
      view |> element("#save-model") |> render_click()
      new_id = List.last(Repo.reload!(model).metrics)["id"]
      render_click(view, "move-metric", %{"id" => new_id, "x" => 14, "y" => 1})
      view |> element("#save-model") |> render_click()
      assert [%{"key" => "A"}, %{"key" => "B", "x" => 14, "y" => 1}] = Repo.reload!(model).metrics
      assert has_element?(view, "#delete-metric-#{new_id}[data-confirm][type=button]")
      view |> element("#delete-metric-#{new_id}") |> render_click()
      refute has_element?(view, "#metric_name[value='New metric']")
      view |> element("#undo") |> render_click()
      assert has_element?(view, "#metric-name-#{new_id}", "New metric")
    end

    test "unselected cards have a confirmed delete button and deletion can be undone", %{
      conn: conn,
      scope: scope
    } do
      a = metric_fixture(%{"name" => "Revenue"})
      b = metric_fixture(%{"name" => "Costs", "key" => "B", "x" => 14})
      model = model_fixture(scope, %{metrics: [a, b]})
      {:ok, view, _} = live(conn, ~p"/models/#{model.id}")

      assert has_element?(view, "#metrics-#{b["id"]}[data-selected=false]")

      assert has_element?(
               view,
               "#delete-metric-#{b["id"]}[aria-label='Delete Costs'][data-confirm*='Costs'][data-confirm*='(B)'] .hero-trash"
             )

      view |> element("#delete-metric-#{b["id"]}") |> render_click()
      refute has_element?(view, "#metrics-#{b["id"]}")
      assert has_element?(view, "#metrics-#{a["id"]}")
      view |> element("#save-model") |> render_click()
      assert Repo.reload!(model).metrics == [a]

      view |> element("#undo") |> render_click()
      assert has_element?(view, "#metrics-#{b["id"]}")
    end

    test "adds at an explicit canvas position and selects the new metric for editing", %{
      conn: conn,
      model: model
    } do
      {:ok, view, _} = live(conn, ~p"/models/#{model.id}")

      assert has_element?(
               view,
               "#model-canvas[data-editable=true][data-card-width='240'][data-card-height='120']"
             )

      render_click(view, "add-metric", %{"x" => 15, "y" => 14})

      assert has_element?(
               view,
               "#metrics > [data-selected=true][data-grid-x='15'][data-grid-y='14'] #metric_name[value='New metric']"
             )

      assert has_element?(view, "#metric_name[value='New metric']")
      assert has_element?(view, "#save-status", "Unsaved changes")
      view |> element("#save-model") |> render_click()

      assert [%{"key" => "A"}, %{"key" => "B", "x" => 15, "y" => 14}] =
               Repo.reload!(model).metrics

      {:ok, reopened, _} = live(conn, ~p"/models/#{model.id}")
      assert has_element?(reopened, "#metrics > [data-grid-x='15'][data-grid-y='14']")
    end

    test "adds and saves signed positions beyond former limits", %{conn: conn, model: model} do
      {:ok, view, _} = live(conn, ~p"/models/#{model.id}")

      render_click(view, "add-metric", %{"x" => "-201", "y" => "1201"})
      assert has_element?(view, "#metrics > [data-grid-x='-201'][data-grid-y='1201']")

      render_click(view, "add-metric", %{"x" => 201, "y" => -1201})
      assert has_element?(view, "#metrics > [data-grid-x='201'][data-grid-y='-1201']")

      view |> element("#save-model") |> render_click()

      assert [
               %{"x" => 0, "y" => 0},
               %{"x" => -201, "y" => 1201},
               %{"x" => 201, "y" => -1201}
             ] = Repo.reload!(model).metrics
    end

    test "undo removes a newly placed metric", %{conn: conn, model: model} do
      {:ok, view, _} = live(conn, ~p"/models/#{model.id}")
      render_click(view, "add-metric", %{"x" => 15, "y" => 14})
      assert has_element?(view, "#metrics > [data-grid-x='15'][data-grid-y='14']")
      view |> element("#undo") |> render_click()
      refute has_element?(view, "#metrics > [data-grid-x='15'][data-grid-y='14']")
      view |> element("#save-model") |> render_click()
      assert Repo.reload!(model).metrics == model.metrics
    end

    test "invalid, incomplete, or occupied creation positions do not change the model", %{
      conn: conn,
      model: model
    } do
      {:ok, view, _} = live(conn, ~p"/models/#{model.id}")

      for params <- [
            %{"x" => 0, "y" => 0},
            %{"x" => "1.5", "y" => 2},
            %{"x" => "2oops", "y" => 2},
            %{"x" => "9007199254740992", "y" => 2},
            %{"x" => 2, "y" => nil},
            %{"x" => 2},
            %{"y" => 2}
          ] do
        render_click(view, "add-metric", params)
        assert has_element?(view, "#flash-error", "valid grid point")
        assert has_element?(view, "#save-status", "All changes saved")
        refute has_element?(view, "#metric_name[value='New metric']")
      end

      assert Repo.reload!(model).metrics == model.metrics
    end

    test "explicit placement still enforces the 100-metric limit", %{conn: conn, scope: scope} do
      metrics =
        for index <- 0..99 do
          key = <<?A + div(index, 26)>> <> <<?A + rem(index, 26)>>
          {x, y} = Canvas.default_position(rem(index, 3), div(index, 3))
          Examples.metric(key, "Metric #{key}", "0", x, y)
        end

      model = model_fixture(scope, %{metrics: metrics})
      {:ok, view, _} = live(conn, ~p"/models/#{model.id}")
      render_click(view, "add-metric", %{"x" => 150, "y" => 600})
      assert has_element?(view, "#flash-error", "cannot add more")
      assert has_element?(view, "#metrics > [data-metric-id]:nth-child(100)")
      refute has_element?(view, "#metrics > [data-metric-id]:nth-child(101)")
      assert Repo.reload!(model).metrics == metrics
    end

    test "a card can sit halfway between rows, save, and reopen on the dot grid", %{
      conn: conn,
      scope: scope
    } do
      a = metric_fixture(%{"name" => "Visitors"})
      b = metric_fixture(%{"key" => "B", "name" => "Conversion rate", "y" => 12})

      c =
        metric_fixture(%{
          "key" => "C",
          "name" => "Customers",
          "input" => "=A * B",
          "x" => 14,
          "y" => 12
        })

      model = model_fixture(scope, %{metrics: [a, b, c]})
      {:ok, view, _} = live(conn, ~p"/models/#{model.id}")

      assert has_element?(view, "#model-canvas[data-grid-step='20']")
      assert has_element?(view, "#model-canvas[data-link-bend='50']")

      assert has_element?(
               view,
               "#connection-#{a["id"]}-#{c["id"]}[data-source-id='#{a["id"]}'][data-target-id='#{c["id"]}']"
             )

      render_click(view, "move-metric", %{"id" => c["id"], "x" => 14, "y" => 6})
      assert has_element?(view, "#metrics-#{c["id"]}[style*='top: 152px;']")
      assert has_element?(view, "#model-canvas .dependency-path[d$='312 212']")
      view |> element("#save-model") |> render_click()

      moved = List.last(Repo.reload!(model).metrics)
      assert moved["y"] == 6
      {_, top_a} = Canvas.pixel_position(a)
      {_, top_b} = Canvas.pixel_position(b)
      {_, top_c} = Canvas.pixel_position(moved)
      assert top_c == div(top_a + top_b, 2)

      {:ok, reopened, _} = live(conn, ~p"/models/#{model.id}")
      assert has_element?(reopened, "#metrics-#{c["id"]}[data-grid-y='6'][style*='top: 152px;']")
    end

    test "moves by one dot and undo restores that exact position", %{
      conn: conn,
      model: model
    } do
      {:ok, view, _} = live(conn, ~p"/models/#{model.id}")
      id = hd(model.metrics)["id"]
      assert has_element?(view, "#metrics-#{id}[style*='left: 32px;']")
      render_click(view, "move-metric", %{"id" => id, "x" => 1, "y" => 0})
      assert has_element?(view, "#metrics-#{id}[data-grid-x='1'][style*='left: 52px;']")
      render_click(view, "move-metric", %{"id" => id, "x" => 1, "y" => 1})
      assert has_element?(view, "#metrics-#{id}[data-grid-y='1'][style*='top: 52px;']")
      view |> element("#undo") |> render_click()
      assert has_element?(view, "#metrics-#{id}[data-grid-y='0'][style*='top: 32px;']")
      view |> element("#save-model") |> render_click()
      assert [%{"x" => 1, "y" => 0}] = Repo.reload!(model).metrics
    end

    test "moves cross zero and accept unbounded integer coordinates", %{
      conn: conn,
      model: model
    } do
      {:ok, view, _} = live(conn, ~p"/models/#{model.id}")
      id = hd(model.metrics)["id"]

      render_click(view, "move-metric", %{"id" => id, "x" => -1, "y" => 0})
      render_click(view, "move-metric", %{"id" => id, "x" => -1, "y" => -1})
      assert has_element?(view, "#metrics-#{id}[data-grid-x='-1'][data-grid-y='-1']")

      render_click(view, "move-metric", %{"id" => id, "x" => "201", "y" => "-1201"})
      assert has_element?(view, "#metrics-#{id}[data-grid-x='201'][data-grid-y='-1201']")
      view |> element("#save-model") |> render_click()
      assert [%{"x" => 201, "y" => -1201}] = Repo.reload!(model).metrics

      {:ok, reopened, _} = live(conn, ~p"/models/#{model.id}")
      assert has_element?(reopened, "#metrics-#{id}[data-grid-x='201'][data-grid-y='-1201']")
    end

    test "invalid or unchanged moves do not create a draft or undo entry", %{
      conn: conn,
      model: model
    } do
      {:ok, view, _} = live(conn, ~p"/models/#{model.id}")
      id = hd(model.metrics)["id"]

      for {x, y, metric_id} <- [
            {0, 0, id},
            {"1.5", 0, id},
            {"1oops", 0, id},
            {9_007_199_254_740_992, 0, id},
            {nil, 0, id},
            {1, 1, Ecto.UUID.generate()}
          ] do
        render_click(view, "move-metric", %{"id" => metric_id, "x" => x, "y" => y})
        assert has_element?(view, "#save-status", "All changes saved")
        assert has_element?(view, "#undo[disabled]")
      end

      assert Repo.reload!(model).metrics == model.metrics
    end

    test "deleting the last metric can be saved and reopened", %{conn: conn, model: model} do
      {:ok, view, _} = live(conn, ~p"/models/#{model.id}")
      render_click(view, "delete-metric", %{"id" => hd(model.metrics)["id"]})
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
      render_click(view, "delete-metric", %{"id" => a["id"]})
      view |> element("#metrics-#{b["id"]}") |> render_click()
      assert has_element?(view, "#metrics-#{b["id"]} #metric-error")
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
      view |> element("#metric-note-#{metric["id"]}") |> render_click()
      view |> form("#note-form", note: %{notes: ""}) |> render_submit()
      view |> element("#save-model") |> render_click()
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
      assert data["version"] == 2
      assert data["metrics"] == model.metrics
      refute Map.has_key?(data, "user_id")
      refute Map.has_key?(data, "user")
    end
  end
end
