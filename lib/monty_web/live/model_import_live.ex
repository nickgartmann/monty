defmodule MontyWeb.ModelImportLive do
  use MontyWeb, :live_view

  alias Monty.{ModelFile, Models}

  @impl true
  def mount(_, _, socket) do
    {:ok,
     assign(socket,
       page_title: "Import a model",
       form: to_form(%{"json" => ""}, as: :import),
       error: nil
     )}
  end

  @impl true
  def handle_event("import", %{"import" => %{"json" => json}}, socket) do
    with {:ok, attrs} <- ModelFile.decode(json),
         {:ok, model} <- Models.create_model(socket.assigns.current_scope, attrs) do
      {:noreply,
       socket
       |> put_flash(:info, "Imported as a private model.")
       |> push_navigate(to: ~p"/models/#{model.id}")}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        errors =
          Enum.map_join(changeset.errors, "; ", fn {field, {message, _}} ->
            "#{field}: #{message}"
          end)

        {:noreply, assign(socket, form: to_form(%{"json" => json}, as: :import), error: errors)}

      {:error, error} when is_binary(error) ->
        {:noreply, assign(socket, form: to_form(%{"json" => json}, as: :import), error: error)}

      _ ->
        {:noreply, put_flash(socket, :error, "Sign in to import a model.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active={:library}>
      <.link navigate={~p"/library"} class="button-ghost mb-6"><.icon
        name="hero-arrow-left"
        class="size-4"
      />My models</.link>
      <p class="eyebrow">Pick up where you left off</p>
      <h1 class="mb-3 mt-3 text-3xl font-semibold tracking-tight text-slate-900">Import a model</h1>
      <p class="mb-8 text-sm leading-6 text-slate-500">
        Paste the contents of a Monty JSON export. We'll create a private copy in your account, with all its assumptions and formulas intact.
      </p>
      <.form for={@form} id="import-model-form" phx-submit="import" class="surface p-6">
        <.input
          field={@form[:json]}
          label="Monty model JSON"
          type="textarea"
          rows="12"
          maxlength={ModelFile.max_bytes()}
          required
          class="form-input font-mono text-xs"
        />
        <p :if={@error} id="import-error" role="alert" class="mb-4 text-sm text-rose-600">{@error}</p>
        <div class="flex items-center justify-between gap-4">
          <p class="text-xs text-slate-400">Up to 100 metrics · 2.5 MB · Monty formats v1 & v2</p>
          <button
            type="submit"
            id="import-submit"
            class="button-primary"
            phx-disable-with="Importing…"
          ><.icon name="hero-arrow-up-tray" class="size-4" />Import model</button>
        </div>
      </.form>
    </Layouts.app>
    """
  end
end
