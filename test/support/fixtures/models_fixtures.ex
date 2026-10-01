defmodule Monty.ModelsFixtures do
  @moduledoc "Fixtures for model domain tests."

  alias Monty.Models

  def scope_fixture, do: Monty.AccountsFixtures.user_scope_fixture()

  def metric_fixture(attrs \\ %{}) do
    Map.merge(
      %{
        "id" => Ecto.UUID.generate(),
        "key" => "A",
        "name" => "Revenue",
        "input" => "10 to 20",
        "distribution" => "uniform",
        "notes" => "",
        "x" => 0,
        "y" => 0
      },
      attrs
    )
  end

  def model_fixture(scope, attrs \\ %{}) do
    defaults = %{
      title: "Fixture estimate",
      description: "A useful description",
      visibility: :private,
      metrics: [metric_fixture()]
    }

    {:ok, model} = Models.create_model(scope, Map.merge(defaults, attrs))
    model
  end
end
