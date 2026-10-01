# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
import Ecto.Query

alias Monty.{Accounts, Examples, Models, Repo}
alias Monty.Accounts.Scope
alias Monty.Models.Model

# These are original example models, not imported Guesstimate production data.
# No password or real email account is created for the example owner.
owner =
  Accounts.get_user_by_email("examples@monty.invalid") ||
    case Accounts.register_user(%{email: "examples@monty.invalid"}) do
      {:ok, user} ->
        user

      {:error, changeset} ->
        raise "Example owner could not be created: #{inspect(changeset.errors)}"
    end

scope = Scope.for_user(owner)

for attrs <- Examples.all() do
  unless Repo.exists?(from m in Model, where: m.user_id == ^owner.id and m.title == ^attrs.title) do
    case Models.create_model(scope, attrs) do
      {:ok, _model} ->
        :ok

      {:error, changeset} ->
        raise "Example model could not be created: #{inspect(changeset.errors)}"
    end
  end
end
