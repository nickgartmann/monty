defmodule Monty.ModelFileTest do
  use ExUnit.Case, async: true
  alias Monty.{Examples, ModelFile, Models}
  alias Monty.Models.Model

  test "every maximal-text supported model can round-trip within the shared byte budget" do
    metrics =
      for index <- 0..99 do
        key = <<?A + div(index, 26)>> <> <<?A + rem(index, 26)>>

        Examples.metric(
          key,
          String.duplicate("\u0001", 120),
          String.duplicate("\u0001", 1000),
          rem(index, 12),
          div(index, 12)
        )
        |> Map.put("notes", String.duplicate("\u0001", 2000))
      end

    model = %Model{
      title: String.duplicate("T", 120),
      description: String.duplicate("\u0001", 4000),
      metrics: metrics
    }

    assert Models.change_model(model).valid?
    assert {:ok, json} = ModelFile.encode(model)
    assert byte_size(json) > 250_000
    assert {:ok, attrs} = ModelFile.decode(json)
    assert attrs["metrics"] == metrics
    assert Models.change_model(%Model{}, attrs).valid?
  end

  test "exports do not include ownership or visibility, and imports always default to private" do
    model = struct(Model, Examples.demo())
    assert {:ok, json} = ModelFile.encode(model)
    assert {:ok, attrs} = ModelFile.decode(json)
    assert attrs["visibility"] == "private"
    refute Map.has_key?(Jason.decode!(json), "user_id")
  end
end
