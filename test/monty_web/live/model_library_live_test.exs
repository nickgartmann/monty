defmodule MontyWeb.ModelLibraryLiveTest do
  use MontyWeb.ConnCase

  import Phoenix.LiveViewTest
  import Monty.AccountsFixtures

  alias Monty.Accounts.Scope
  alias Monty.Models

  describe "explore" do
    test "offers a demo and sends guests to registration to save a model", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      assert has_element?(view, "#model-library")
      assert has_element?(view, "#explore-try-model[href='/try']")
      assert has_element?(view, "#explore-new-model[href='/users/register']")
      assert has_element?(view, "#model-search")
    end

    test "shows public models but not private or unlisted models to a guest", %{conn: conn} do
      user = user_fixture()
      public = create_model(user, "Public forecast", :public)
      private = create_model(user, "Private forecast", :private)
      unlisted = create_model(user, "Unlisted forecast", :unlisted)

      {:ok, view, _html} = live(conn, "/explore")

      assert has_element?(view, "#models-grid a[href='/models/#{public.id}']")
      refute has_element?(view, "#models-grid a[href='/models/#{private.id}']")
      refute has_element?(view, "#models-grid a[href='/models/#{unlisted.id}']")
    end

    test "search filters the streamed cards and can be cleared", %{conn: conn} do
      user = user_fixture()
      match = create_model(user, "Coffee shop forecast", :public)
      other = create_model(user, "Bookshop forecast", :public)

      {:ok, view, _html} = live(conn, "/explore")

      view |> form("#model-search", search: %{query: "Coffee"}) |> render_change()

      assert has_element?(view, "#models-grid a[href='/models/#{match.id}']")
      refute has_element?(view, "#models-grid a[href='/models/#{other.id}']")

      view |> form("#model-search", search: %{query: "unfindable phrase"}) |> render_change()
      assert has_element?(view, "#models-empty")

      view |> element("#models-empty-clear") |> render_click()
      refute has_element?(view, "#models-empty")
      assert has_element?(view, "#models-grid a[href='/models/#{other.id}']")
    end
  end

  describe "my library" do
    test "lists only the owner's models and safely deletes one", %{conn: conn} do
      user = user_fixture()
      another_user = user_fixture()
      own = create_model(user, "My private question", :private)
      another = create_model(another_user, "Someone else's question", :public)

      {:ok, view, _html} = conn |> log_in_user(user) |> live("/library")

      assert has_element?(view, "#library-new-model[href='/models/new']")
      assert has_element?(view, "#models-grid a[href='/models/#{own.id}']")
      refute has_element?(view, "#models-grid a[href='/models/#{another.id}']")
      assert has_element?(view, "#delete-model-#{own.id}[data-confirm]")

      view |> element("#delete-model-#{own.id}") |> render_click()

      refute has_element?(view, "#models-grid a[href='/models/#{own.id}']")
      assert {:error, :not_found} = Models.get_model(Scope.for_user(user), own.id)
    end

    test "cannot delete another person's model by forging an event", %{conn: conn} do
      user = user_fixture()
      another_user = user_fixture()
      another = create_model(another_user, "Another person's model", :public)

      {:ok, view, _html} = conn |> log_in_user(user) |> live("/library")

      render_hook(view, "delete", %{"id" => another.id})

      assert {:ok, _model} = Models.get_model(Scope.for_user(another_user), another.id)
    end
  end

  defp create_model(user, title, visibility) do
    {:ok, model} =
      Models.create_model(Scope.for_user(user), %{
        title: title,
        description: "A working estimate",
        visibility: visibility
      })

    model
  end
end
