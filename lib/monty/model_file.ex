defmodule Monty.ModelFile do
  @moduledoc "A bounded, versioned interchange format for Monty models (not legacy Guesstimate data)."
  # Enough for 100 metrics at every schema text limit, even when JSON expands
  # each character into a six-byte escape. Export and import share this budget.
  @max_bytes 2_500_000

  def max_bytes, do: @max_bytes

  def encode(model) do
    data = %{
      format: "monty",
      version: 1,
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
      {:ok, %{"format" => "monty", "version" => 1, "title" => title, "metrics" => metrics} = data}
      when is_binary(title) and is_list(metrics) ->
        {:ok,
         %{
           "title" => title,
           "description" => data["description"],
           "metrics" => metrics,
           "visibility" => "private"
         }}

      {:ok, _} ->
        {:error, "Use a Monty version 1 export. Legacy Guesstimate files need conversion first."}

      {:error, _} ->
        {:error, "This is not valid JSON. Paste the complete contents of your export."}
    end
  end

  def decode(_), do: size_error()

  defp size_error, do: {:error, "The export is too large. The limit is 2.5 MB and 100 metrics."}
end
