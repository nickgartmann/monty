defmodule MontyWeb.PertTest do
  use MontyWeb.ConnCase

  import Phoenix.LiveViewTest

  test "sandbox previews PERT and recovers after an invalid mode", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/try")
    assert has_element?(view, "#metric-form")
    view |> element("#formula-help") |> render_click()
    assert has_element?(view, "#pert-guide", "=pert(10, 15, 30)")

    view |> form("#metric-form", metric: %{input: "=pert(10, 20, 30)"}) |> render_change()
    refute has_element?(view, "#metric-error")
    assert has_element?(view, "#metric-statistics")
    assert has_element?(view, "#stat-median")

    view |> form("#metric-form", metric: %{input: "=pert(10, 31, 30)"}) |> render_change()
    assert has_element?(view, "#metric-error")

    view |> form("#metric-form", metric: %{input: "=pert(-20%, 0%, 30%)"}) |> render_change()
    refute has_element?(view, "#metric-error")
    assert has_element?(view, "#metric-statistics")
    assert has_element?(view, "#stat-median")
  end
end
