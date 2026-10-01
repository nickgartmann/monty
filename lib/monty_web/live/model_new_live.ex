defmodule MontyWeb.ModelNewLive do
  use MontyWeb, :live_view

  alias Monty.{Examples, Models}
  alias Monty.Models.Model

  @impl true
  def mount(_params, _session, socket) do
    changeset = Models.change_model(%Model{}, %{visibility: :private})

    {:ok,
     socket
     |> assign_new(:current_scope, fn -> nil end)
     |> assign(:page_title, "New model")
     |> assign(:form, to_form(changeset, as: :model))}
  end

  @impl true
  def handle_event("validate", %{"model" => params}, socket) do
    changeset =
      %Model{}
      |> Models.change_model(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset, as: :model))}
  end

  def handle_event("save", %{"model" => params}, socket) do
    attrs = Map.put(params, "metrics", Examples.starter_metrics())

    case Models.create_model(socket.assigns.current_scope, attrs) do
      {:ok, model} ->
        {:noreply,
         socket
         |> put_flash(:info, "Model created. Start adding your assumptions.")
         |> push_navigate(to: ~p"/models/#{model.id}")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :model))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active={:library} wide>
      <div id="new-model" class="mx-auto w-full max-w-5xl px-5 pb-24 pt-10 sm:px-8 lg:px-10">
        <.link
          navigate={~p"/library"}
          id="new-model-back"
          class="inline-flex items-center gap-2 rounded-sm text-sm font-medium text-slate-500 transition hover:text-teal-800 focus-visible:outline-2 focus-visible:outline-teal-600"
        >
          <.icon name="hero-arrow-left" class="size-4" /> Back to library
        </.link>
        <div class="mt-12 grid gap-12 lg:grid-cols-[minmax(0,1fr)_minmax(0,1.1fr)] lg:gap-16">
          <div>
            <p class="eyebrow mb-4">A new question</p>
            <h1 class="text-4xl font-semibold leading-tight tracking-[-0.045em] text-slate-900 sm:text-5xl">
              Start with what you’re curious about.
            </h1>
            <p class="mt-5 max-w-md text-base leading-relaxed text-slate-600">
              Give your model a name and a little context. You can add uncertain inputs,
              connect them, and explore outcomes in the editor.
            </p>
            <div class="mt-10 flex items-start gap-3 border-t border-slate-200 pt-6 text-sm leading-relaxed text-slate-500">
              <div class="flex size-8 shrink-0 items-center justify-center rounded-lg bg-teal-50 text-teal-700">
                <.icon name="hero-lock-closed" class="size-4" />
              </div>
              <p>Models are private by default. Share only when you’re ready.</p>
            </div>
          </div>

          <div class="surface self-start rounded-3xl border border-slate-200 bg-white p-6 shadow-[0_22px_65px_-45px_rgba(15,45,49,0.3)] sm:p-9">
            <div class="mb-7 flex items-center gap-3 border-b border-slate-100 pb-6">
              <div class="flex size-10 items-center justify-center rounded-xl bg-teal-50 text-teal-700">
                <.icon name="hero-square-3-stack-3d" class="size-5" />
              </div>
              <div>
                <h2 class="text-lg font-semibold tracking-tight text-slate-900">Model details</h2>
                <p class="text-xs text-slate-500">You can change these later.</p>
              </div>
            </div>
            <.form
              for={@form}
              id="new-model-form"
              phx-change="validate"
              phx-submit="save"
              class="space-y-5"
            >
              <div>
                <.input
                  field={@form[:title]}
                  type="text"
                  label="Title"
                  placeholder="e.g. How many customers might we reach?"
                  maxlength="120"
                  autocomplete="off"
                  required
                  class="form-input w-full"
                />
                <p class="mt-1.5 text-xs text-slate-500">A clear question makes a better model.</p>
              </div>
              <.input
                field={@form[:description]}
                type="textarea"
                label="Description"
                placeholder="What are you trying to understand?"
                rows="4"
                class="form-input w-full min-h-28 resize-y"
              />
              <div>
                <.input
                  field={@form[:visibility]}
                  type="select"
                  label="Visibility"
                  options={[
                    {"Private — only you", "private"},
                    {"Unlisted — anyone with the link", "unlisted"},
                    {"Public — discoverable by everyone", "public"}
                  ]}
                  class="form-input w-full"
                />
                <p class="mt-1.5 text-xs text-slate-500">
                  Public models can appear in Explore. Unlisted models are link-only.
                </p>
              </div>
              <div class="flex flex-col-reverse gap-3 border-t border-slate-100 pt-6 sm:flex-row sm:items-center sm:justify-end">
                <.link navigate={~p"/library"} id="new-model-cancel" class="button-ghost text-center">Cancel</.link>
                <button
                  id="new-model-submit"
                  type="submit"
                  phx-disable-with="Creating model…"
                  class="button-primary inline-flex items-center justify-center gap-2"
                >
                  Create model <.icon name="hero-arrow-right" class="size-4" />
                </button>
              </div>
            </.form>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
