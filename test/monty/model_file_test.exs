defmodule Monty.ModelFileTest do
  use ExUnit.Case, async: true
  alias Monty.{Canvas, Examples, ModelFile, Models}
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
    assert Jason.decode!(json)["version"] == 2
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

  test "version 2 round-trips fine coordinates without changing ownership or attributes" do
    metric = Examples.metric("A", "Fine position", "42", 13, 23)
    model = %Model{title: "Fine", metrics: [metric]}
    assert {:ok, json} = ModelFile.encode(model)

    assert {:ok, %{"metrics" => [^metric], "visibility" => "private"}} =
             ModelFile.decode(json)

    assert Jason.decode!(json)["version"] == 2
  end

  test "version 1 imports convert every metric to the nearest dot before validation" do
    legacy = Examples.metric("A", "Old grid", "42", 11, 99)

    export = %{
      format: "monty",
      version: 1,
      title: "Older estimate",
      description: "Keep this",
      user_id: "forged",
      visibility: "public",
      metrics: [legacy]
    }

    assert {:ok, attrs} = export |> Jason.encode!() |> ModelFile.decode()

    assert attrs["metrics"] == [
             legacy
             |> Map.put("x", elem(Canvas.from_legacy_position(11, 99), 0))
             |> Map.put("y", elem(Canvas.from_legacy_position(11, 99), 1))
           ]

    assert attrs["description"] == "Keep this"
    assert attrs["visibility"] == "private"
    refute Map.has_key?(attrs, "user_id")
    assert Models.change_model(%Model{}, attrs).valid?

    for invalid <- [
          Map.put(legacy, "x", -1),
          Map.put(legacy, "x", 12),
          Map.put(legacy, "y", 100),
          Map.put(legacy, "x", "11"),
          Map.delete(legacy, "y"),
          "not a metric"
        ] do
      assert {:error, message} =
               export |> Map.put(:metrics, [invalid]) |> Jason.encode!() |> ModelFile.decode()

      assert message =~ "invalid metric coordinates"
    end
  end

  test "file size bound and unrecognized versions are rejected" do
    assert {:error, message} = ModelFile.decode(String.duplicate("x", ModelFile.max_bytes() + 1))
    assert message =~ "too large"

    assert {:error, message} =
             ModelFile.decode(~s({"format":"monty","version":3,"title":"Bad","metrics":[]}))

    assert message =~ "version 1 or 2"
  end
end
