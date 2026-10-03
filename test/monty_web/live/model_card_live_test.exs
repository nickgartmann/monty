defmodule MontyWeb.ModelCardLiveTest do
  use MontyWeb.ConnCase

  import Phoenix.LiveViewTest
  import Monty.ModelsFixtures

  alias Monty.Accounts.Scope
  alias Monty.Repo

  describe "inline card configuration" do
    setup :register_and_log_in_user

    setup %{user: user} do
      a = metric_fixture(%{"name" => "Revenue", "notes" => "Based on last year"})
      b = metric_fixture(%{"key" => "B", "name" => "Costs", "x" => 14})
      model = model_fixture(Scope.for_user(user), %{metrics: [a, b]})
      %{model: model, a: a, b: b}
    end

    test "inline fields follow the active card and typing applies a draft without Apply", %{
      conn: conn,
      model: model,
      a: a,
      b: b
    } do
      {:ok, view, _} = live(conn, ~p"/models/#{model.id}")
      assert has_element?(view, "#metrics-#{a["id"]} #metric_name")
      assert has_element?(view, "#metrics-#{a["id"]} #metric_input")
      refute has_element?(view, "#metric-detail")
      refute has_element?(view, "#estimate-help")
      refute has_element?(view, "#range-distribution-help")
      refute has_element?(view, "#apply-metric")
      refute has_element?(view, "#metric-statistics")
      refute has_element?(view, "#move-down")
      refute has_element?(view, "#delete-metric")
      refute has_element?(view, "#metrics-#{b["id"]} #metric-form")

      view |> element("#metric-name-#{b["id"]}") |> render_click()
      assert_push_event(view, "focus-metric-field", %{id: "metric_name"})
      assert has_element?(view, "#metrics-#{b["id"]} #metric_name[value='Costs']")
      refute has_element?(view, "#metrics-#{a["id"]} #metric-form")

      view |> form("#metric-form", metric: %{name: "Operating costs"}) |> render_change()
      assert has_element?(view, "#metrics-#{b["id"]} #metric_name[value='Operating costs']")
      assert has_element?(view, "#save-status", "Unsaved changes")
      assert Repo.reload!(model).metrics == model.metrics
      view |> element("#metric-formula-#{a["id"]}") |> render_click()
      assert_push_event(view, "focus-metric-field", %{id: "metric_input"})
      assert has_element?(view, "#metrics-#{a["id"]} #metric_input")
      view |> form("#metric-form", metric: %{input: "42"}) |> render_change()
      assert has_element?(view, "#metrics-#{a["id"]} [data-metric-summary]", "42.0")
      view |> element("#save-model") |> render_click()
      assert [%{"input" => "42"}, %{"name" => "Operating costs"}] = Repo.reload!(model).metrics
    end

    test "clicking the active card preserves invalid field edits and shows validation in the card",
         %{
           conn: conn,
           model: model,
           a: a
         } do
      {:ok, view, _} = live(conn, ~p"/models/#{model.id}")
      view |> form("#metric-form", metric: %{name: ""}) |> render_change()
      assert has_element?(view, "#metrics-#{a["id"]} #metric-validation-name")
      view |> element("#metrics-#{a["id"]}") |> render_click()
      assert has_element?(view, "#metric_name[value='']")
      refute has_element?(view, "#apply-metric")

      view |> element("#metric-note-#{a["id"]}") |> render_click()
      view |> form("#note-form", note: %{notes: "Updated source"}) |> render_submit()
      assert has_element?(view, "#note-tooltip-#{a["id"]}", "Updated source")
      assert has_element?(view, "#metric_name[value='']")
      assert has_element?(view, "#save-model[disabled]")
    end

    test "distribution dropdown appears only for a valid numeric range", %{
      conn: conn,
      model: model,
      a: a,
      b: b
    } do
      {:ok, view, _} = live(conn, ~p"/models/#{model.id}")
      assert has_element?(view, "#metrics-#{a["id"]} #metric_distribution")
      assert has_element?(view, "#metrics-#{b["id"]} svg[data-distribution=uniform]")
      refute has_element?(view, "#metrics-#{b["id"]} #metric_distribution")

      view |> form("#metric-form", metric: %{distribution: "lognormal"}) |> render_change()

      for input <- ["42", "=normal(42, 2)", "10 to", "20 to 10", "10 to 10"] do
        view |> form("#metric-form", metric: %{input: input}) |> render_change()
        refute has_element?(view, "#metric_distribution")

        assert has_element?(
                 view,
                 "#metric-form input[type=hidden][name='metric[distribution]'][value='lognormal']"
               )
      end

      view |> form("#metric-form", metric: %{input: "10 to 20"}) |> render_change()
      assert has_element?(view, "#metrics-#{a["id"]} #metric_distribution")
      assert has_element?(view, "#metrics-#{a["id"]} svg[data-distribution=lognormal]")
      refute has_element?(view, "#metric-form input[type=hidden][name='metric[distribution]']")
    end

    test "distribution selection updates active and inactive range icons before global save", %{
      conn: conn,
      model: model,
      a: a,
      b: b
    } do
      {:ok, view, _} = live(conn, ~p"/models/#{model.id}")

      for distribution <- ["normal", "uniform", "lognormal"] do
        view
        |> form("#metric-form", metric: %{distribution: distribution})
        |> render_change()

        assert has_element?(view, "#metrics-#{a["id"]} #metric_distribution")
        assert has_element?(view, "#metrics-#{a["id"]} svg[data-distribution=#{distribution}]")

        if distribution != "uniform" do
          assert has_element?(view, "#save-status", "Unsaved changes")
        end

        view |> element("#metrics-#{b["id"]}") |> render_click()
        assert has_element?(view, "#metrics-#{a["id"]} svg[data-distribution=#{distribution}]")
        view |> element("#metrics-#{a["id"]}") |> render_click()
      end

      assert Repo.reload!(model).metrics == model.metrics
      view |> element("#save-model") |> render_click()
      assert hd(Repo.reload!(model).metrics)["distribution"] == "lognormal"
    end

    test "note modal applies only the chosen card's note, persists on save, and supports undo", %{
      conn: conn,
      model: model,
      a: a,
      b: b
    } do
      {:ok, view, _} = live(conn, ~p"/models/#{model.id}")

      assert has_element?(
               view,
               "#metric-note-#{a["id"]}[aria-describedby='note-tooltip-#{a["id"]}']"
             )

      assert has_element?(view, "#note-tooltip-#{a["id"]}[role=tooltip]", "Based on last year")
      view |> element("#metric-note-#{b["id"]}") |> render_click()
      assert has_element?(view, "#note-dialog[role=dialog][aria-modal=true]")
      assert has_element?(view, "#note-dialog-title", "Costs")
      assert has_element?(view, "#metrics-#{a["id"]}[data-selected=true]")

      render_submit(view, "save-note", %{
        "note" => %{"notes" => "Vendor estimate", "id" => a["id"], "name" => "Forged"}
      })

      refute has_element?(view, "#note-modal")
      assert has_element?(view, "#note-tooltip-#{b["id"]}", "Vendor estimate")
      assert Repo.reload!(model).metrics == model.metrics
      view |> element("#save-model") |> render_click()

      assert [
               %{"notes" => "Based on last year"},
               %{"notes" => "Vendor estimate", "name" => "Costs"}
             ] =
               Repo.reload!(model).metrics

      {:ok, reopened, _} = live(conn, ~p"/models/#{model.id}")
      assert has_element?(reopened, "#note-tooltip-#{b["id"]}", "Vendor estimate")
      view |> element("#undo") |> render_click()
      assert has_element?(view, "#note-tooltip-#{b["id"]}", "Add a note")
    end

    test "cancel discards note drafts and oversized notes stay in the modal", %{
      conn: conn,
      model: model,
      a: a
    } do
      {:ok, view, _} = live(conn, ~p"/models/#{model.id}")
      view |> element("#metric-note-#{a["id"]}") |> render_click()
      view |> form("#note-form", note: %{notes: "Discard me"}) |> render_change()
      view |> element("#cancel-note") |> render_click()
      refute has_element?(view, "#note-modal")
      assert has_element?(view, "#save-status", "All changes saved")
      assert has_element?(view, "#note-tooltip-#{a["id"]}", "Based on last year")

      view |> element("#metric-note-#{a["id"]}") |> render_click()
      view |> form("#note-form", note: %{notes: String.duplicate("x", 2001)}) |> render_submit()
      assert has_element?(view, "#note-form")
      assert has_element?(view, "#note-form .form-field p", "at most 2000")
      assert Repo.reload!(model).metrics == model.metrics
      render_click(view, "close-note")
      refute has_element?(view, "#note-modal")
    end
  end

  test "shared model notes are readable but forged note updates cannot mutate them", %{conn: conn} do
    metric = metric_fixture(%{"notes" => "Public assumption"})
    model = model_fixture(scope_fixture(), %{visibility: :public, metrics: [metric]})
    {:ok, view, _} = live(conn, ~p"/models/#{model.id}")
    view |> element("#metric-note-#{metric["id"]}") |> render_click()
    assert has_element?(view, "#note_notes[readonly]")
    refute has_element?(view, "#save-note")
    render_change(view, "validate-note", %{"note" => %{"notes" => "Forged"}})
    render_submit(view, "save-note", %{"note" => %{"notes" => "Forged"}})
    render_click(view, "save")
    assert Repo.reload!(model).metrics == model.metrics
  end
end
