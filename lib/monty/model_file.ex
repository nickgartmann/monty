defmodule Monty.ModelFile do
  @moduledoc "A bounded, versioned interchange format for Monty models (not legacy Guesstimate data)."
  alias Monty.Canvas
  # Enough for 100 metrics at every schema text limit, even when JSON expands
  # each character into a six-byte escape. Export and import share this budget.
  @max_bytes 2_500_000

  def max_bytes, do: @max_bytes

  def encode(model) do
    data = %{
      format: "monty",
      version: 2,
      title: model.title,
      description: model.description,
      metrics: model.metrics
    }

    case Jason.encode(data, pretty: true) do
      {:ok, json} when byte_size(json) <= @max_bytes -> {:ok, json}
      {:ok, _} -> size_error()
      {:error, _} -> {:error, "The model could not be encoded as JSON."}
    end
  end

  def decode(json) when is_binary(json) and byte_size(json) <= @max_bytes do
    case Jason.decode(json) do
      {:ok,
       %{"format" => "monty", "version" => version, "title" => title, "metrics" => metrics} = data}
      when version in [1, 2] and is_binary(title) and is_list(metrics) ->
        with {:ok, metrics} <- import_metrics(metrics, version) do
          {:ok,
           %{
             "title" => title,
             "description" => data["description"],
             "metrics" => metrics,
             "visibility" => "private"
           }}
        end

      {:ok, _} ->
        {:error,
         "Use a Monty version 1 or 2 export. Legacy Guesstimate files need conversion first."}

      {:error, _} ->
        {:error, "This is not valid JSON. Paste the complete contents of your export."}
    end
  end

  def decode(_), do: size_error()

  defp import_metrics(metrics, 2), do: {:ok, metrics}

  defp import_metrics(metrics, 1) do
    if Enum.all?(metrics, fn
         %{"x" => x, "y" => y} -> is_integer(x) and x in 0..11 and is_integer(y) and y in 0..99
         _ -> false
       end) do
      {:ok,
       Enum.map(metrics, fn metric ->
         {x, y} = Canvas.from_legacy_position(metric["x"], metric["y"])
         metric |> Map.put("x", x) |> Map.put("y", y)
       end)}
    else
      {:error, "The version 1 export contains invalid metric coordinates."}
    end
  end

  defp size_error, do: {:error, "The export is too large. The limit is 2.5 MB and 100 metrics."}
end
