defmodule MontyWeb.ModelNewLiveTest do
  use MontyWeb.ConnCase

  import Phoenix.LiveViewTest
  import Monty.AccountsFixtures

  alias Monty.Accounts.Scope
  alias Monty.Models

  test "requires a signed-in user", %{conn: conn} do
    assert {:error, {:redirect, %{to: path}}} = live(conn, "/models/new")
    assert String.starts_with?(path, "/users/log-in")
  end

  test "defaults to private and validates the form", %{conn: conn} do
    user = user_fixture()
    {:ok, view, _html} = conn |> log_in_user(user) |> live("/models/new")

    assert has_element?(view, "#new-model-form")

    assert has_element?(
             view,
             "#new-model-form [name='model[visibility]'] option[value='private'][selected]"
           )

    assert has_element?(view, "#new-model-cancel[href='/library']")

    view |> form("#new-model-form", model: %{title: "", visibility: "private"}) |> render_change()
    assert has_element?(view, "#new-model-form p", "can't be blank")
  end

  test "creates a private model with editable starter assumptions and opens its editor", %{
    conn: conn
  } do
    user = user_fixture()
    scope = Scope.for_user(user)
    {:ok, view, _html} = conn |> log_in_user(user) |> live("/models/new")

    view
    |> form("#new-model-form",
      model: %{
        title: "How many customers?",
        description: "Estimate the first quarter",
        visibility: "private"
      }
    )
    |> render_submit()

    assert [model] = Models.list_models(scope, owned: true)

    assert model.title == "How many customers?"
    assert model.visibility == :private
    assert Enum.map(model.metrics, & &1["key"]) == ["A", "B", "C"]
    assert Enum.map(model.metrics, & &1["input"]) == ["1000 to 2000", "2% to 5%", "=A * B"]
    assert Enum.all?(model.metrics, &match?({:ok, _}, Ecto.UUID.cast(&1["id"])))
    assert_redirect(view, "/models/#{model.id}")
  end
end
