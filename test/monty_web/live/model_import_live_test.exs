defmodule MontyWeb.ModelImportLiveTest do
  use MontyWeb.ConnCase
  import Phoenix.LiveViewTest
  alias Monty.{Examples, ModelFile, Models}
  alias Monty.Accounts.Scope

  test "guests must authenticate", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/models/import")
  end

  describe "import" do
    setup :register_and_log_in_user

    test "valid exports become private owned models regardless of supplied visibility", %{
      conn: conn,
      user: user
    } do
      {:ok, view, _} = live(conn, ~p"/models/import")

      attrs =
        Map.merge(Examples.demo(), %{
          format: "monty",
          version: 2,
          visibility: "public",
          user_id: Ecto.UUID.generate()
        })

      view |> form("#import-model-form", import: %{json: Jason.encode!(attrs)}) |> render_submit()
      {path, _} = assert_redirect(view)

      assert {:ok, model} =
               Models.get_model(Scope.for_user(user), String.replace_prefix(path, "/models/", ""))

      assert model.visibility == :private
      assert model.user_id == user.id
      assert model.metrics == attrs.metrics
    end

    test "version 1 imports preserve older layouts on the new fine grid", %{
      conn: conn,
      user: user
    } do
      {:ok, view, _} = live(conn, ~p"/models/import")
      legacy_metric = Examples.metric("A", "Legacy", "42", 1, 1)

      json =
        Jason.encode!(%{
          format: "monty",
          version: 1,
          title: "Old layout",
          metrics: [legacy_metric]
        })

      view |> form("#import-model-form", import: %{json: json}) |> render_submit()
      {path, _} = assert_redirect(view)

      assert {:ok, model} =
               Models.get_model(Scope.for_user(user), String.replace_prefix(path, "/models/", ""))

      assert [%{"x" => 14, "y" => 11}] = model.metrics
    end

    test "rejects malformed and unsupported data without leaving the form", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/models/import")

      for json <- ["oops", ~s({"version":2}), String.duplicate("x", ModelFile.max_bytes() + 1)] do
        render_submit(view, "import", %{"import" => %{"json" => json}})
        assert has_element?(view, "#import-error")
        assert has_element?(view, "#import-model-form")
      end
    end
  end
end
