defmodule MontyWeb.ModelLibraryLive do
  use MontyWeb, :live_view

  alias Monty.Models

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign_new(:current_scope, fn -> nil end)
     |> assign(:query, "")
     |> assign(:search_form, to_form(%{"query" => ""}, as: :search))
     |> assign(:empty?, true)
     |> stream(:models, [])}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    mine? = socket.assigns.live_action == :mine

    {:noreply,
     socket
     |> assign(:mine?, mine?)
     |> assign(:page_title, if(mine?, do: "My library", else: "Explore models"))
     |> load_models()}
  end

  @impl true
  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    {:noreply,
     socket
     |> assign(:query, query)
     |> assign(:search_form, to_form(%{"query" => query}, as: :search))
     |> load_models()}
  end

  def handle_event("clear_search", _params, socket) do
    {:noreply,
     socket
     |> assign(:query, "")
     |> assign(:search_form, to_form(%{"query" => ""}, as: :search))
     |> load_models()}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope

    result =
      with %{user: %{id: user_id}} <- scope,
           {:ok, %{user_id: ^user_id} = model} <- Models.get_model(scope, id) do
        Models.delete_model(scope, model)
      else
        _ -> {:error, :not_found}
      end

    case result do
      {:ok, _model} ->
        {:noreply,
         socket
         |> put_flash(:info, "Model deleted.")
         |> load_models()}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "This model could not be deleted.")}
    end
  end

  defp load_models(socket) do
    models =
      Models.list_models(socket.assigns.current_scope,
        query: socket.assigns.query,
        owned: socket.assigns.mine?
      )

    socket
    |> assign(:empty?, models == [])
    |> stream(:models, models, reset: true)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      active={if(@mine?, do: :library, else: :explore)}
      wide
    >
      <div id="model-library" class="mx-auto w-full max-w-7xl px-5 pb-24 pt-10 sm:px-8 lg:px-10">
        <%= if @mine? do %>
          <section class="flex flex-col gap-6 border-b border-slate-200 pb-10 sm:flex-row sm:items-end sm:justify-between">
            <div>
              <p class="eyebrow mb-3">Your workspace</p>
              <h1 class="text-4xl font-semibold tracking-[-0.045em] text-slate-900 sm:text-5xl">
                My library
              </h1>
              <p class="mt-3 max-w-xl text-base leading-relaxed text-slate-500">
                The questions you’re working through, all in one place.
              </p>
            </div>
            <div class="flex shrink-0 items-center gap-2">
              <.link navigate={~p"/models/import"} id="library-import-model" class="button-secondary">
                <.icon name="hero-arrow-up-tray" class="size-4" /> Import
              </.link>
              <.link
                navigate={~p"/models/new"}
                id="library-new-model"
                class="button-primary inline-flex shrink-0 items-center justify-center gap-2"
              >
                <.icon name="hero-plus" class="size-4" /> New model
              </.link>
            </div>
          </section>
        <% else %>
          <section class="grid gap-12 border-b border-slate-200 pb-16 pt-8 lg:grid-cols-[minmax(0,1.1fr)_minmax(0,0.9fr)] lg:items-center lg:gap-20 lg:pt-14">
            <div>
              <p class="eyebrow mb-5">A better way to think in numbers</p>
              <h1 class="max-w-3xl text-5xl font-semibold leading-[1.07] tracking-[-0.055em] text-slate-900 sm:text-6xl">
                Less certainty.<br />
                <span class="text-teal-700">Better decisions.</span>
              </h1>
              <p class="mt-7 max-w-xl text-lg leading-relaxed text-slate-600">
                Spreadsheets hide the uncertainty in your assumptions. Monty makes it visible.
                Sketch a model, explore the possible outcomes, and find out which inputs matter.
              </p>
              <div class="mt-9 flex flex-wrap items-center gap-3">
                <.link
                  navigate={~p"/try"}
                  id="explore-try-model"
                  class="button-primary inline-flex items-center justify-center gap-2"
                >
                  Try a model <.icon name="hero-arrow-up-right" class="size-4" />
                </.link>
                <.link
                  navigate={
                    if(@current_scope && @current_scope.user,
                      do: ~p"/models/new",
                      else: ~p"/users/register"
                    )
                  }
                  id="explore-new-model"
                  class="button-secondary inline-flex items-center justify-center gap-2"
                >
                  New model <.icon name="hero-arrow-right" class="size-4" />
                </.link>
              </div>
              <p class="mt-4 text-sm text-slate-400">
                No spreadsheet required. Try it without an account.
              </p>
            </div>

            <div
              aria-label="Example of a model with uncertain inputs"
              class="surface relative overflow-hidden rounded-3xl border border-slate-200 bg-white p-5 shadow-[0_24px_80px_-45px_rgba(15,45,49,0.4)] sm:p-7"
            >
              <div class="flex items-center justify-between border-b border-slate-100 pb-5">
                <div>
                  <p class="text-[11px] font-semibold uppercase tracking-[0.16em] text-teal-700">
                    A simple model
                  </p>
                  <h2 class="mt-1 text-lg font-semibold tracking-tight text-slate-900">
                    What might happen?
                  </h2>
                </div>
                <div class="flex size-9 items-center justify-center rounded-xl bg-teal-50 text-teal-700">
                  <.icon name="hero-chart-bar-square" class="size-5" />
                </div>
              </div>
              <div class="space-y-3 py-5">
                <div class="flex items-center justify-between rounded-2xl border border-slate-100 bg-slate-50/70 p-4">
                  <div class="flex items-center gap-3">
                    <span class="flex size-8 items-center justify-center rounded-lg bg-white text-xs font-bold text-slate-500 shadow-sm">A</span>
                    <span class="text-sm font-medium text-slate-700">Visitors</span>
                  </div>
                  <span class="font-mono text-xs text-slate-500">1,000 – 2,000</span>
                </div>
                <div class="flex items-center justify-between rounded-2xl border border-slate-100 bg-slate-50/70 p-4">
                  <div class="flex items-center gap-3">
                    <span class="flex size-8 items-center justify-center rounded-lg bg-white text-xs font-bold text-slate-500 shadow-sm">B</span>
                    <span class="text-sm font-medium text-slate-700">Conversion</span>
                  </div>
                  <span class="font-mono text-xs text-slate-500">2% – 5%</span>
                </div>
                <div class="flex items-center justify-between rounded-2xl border border-teal-200 bg-teal-50/70 p-4">
                  <div class="flex items-center gap-3">
                    <span class="flex size-8 items-center justify-center rounded-lg bg-teal-700 text-xs font-bold text-white">C</span>
                    <span class="text-sm font-semibold text-slate-800">Customers</span>
                  </div>
                  <span class="font-mono text-xs font-medium text-teal-800">A × B</span>
                </div>
              </div>
              <p class="border-t border-slate-100 pt-4 text-xs leading-relaxed text-slate-500">
                Replace single guesses with ranges. See the shape of what’s possible.
              </p>
            </div>
          </section>
        <% end %>

        <section id="model-results" aria-labelledby="models-heading" class="pt-12 sm:pt-16">
          <div class="flex flex-col gap-6 md:flex-row md:items-end md:justify-between">
            <div>
              <p class="eyebrow mb-2">{if @mine?, do: "Saved work", else: "From the community"}</p>
              <h2
                id="models-heading"
                class="text-2xl font-semibold tracking-[-0.035em] text-slate-900 sm:text-3xl"
              >
                {if @mine?, do: "Your models", else: "Explore models"}
              </h2>
              <p class="mt-2 text-sm text-slate-500">
                {if @mine?,
                  do: "Pick up where you left off.",
                  else: "Start with an idea and make it your own."}
              </p>
            </div>
            <.form
              for={@search_form}
              id="model-search"
              phx-change="search"
              phx-submit="search"
              role="search"
              class="w-full md:max-w-xs"
            >
              <label for="model-search-query" class="sr-only">Search models</label>
              <div class="relative">
                <.icon
                  name="hero-magnifying-glass"
                  class="pointer-events-none absolute left-3.5 top-1/2 size-4 -translate-y-1/2 text-slate-400"
                />
                <.input
                  field={@search_form[:query]}
                  id="model-search-query"
                  type="search"
                  placeholder="Search models"
                  autocomplete="off"
                  class="form-input w-full pl-10 pr-10"
                />
                <button
                  :if={@query != ""}
                  type="button"
                  id="model-search-clear"
                  phx-click="clear_search"
                  aria-label="Clear search"
                  class="absolute right-2 top-1/2 flex size-8 -translate-y-1/2 items-center justify-center rounded-lg text-slate-400 transition hover:bg-slate-100 hover:text-slate-700"
                >
                  <.icon name="hero-x-mark" class="size-4" />
                </button>
              </div>
            </.form>
          </div>

          <div
            :if={@empty?}
            id="models-empty"
            class="mt-8 rounded-3xl border border-dashed border-slate-300 bg-white/70 px-6 py-16 text-center sm:py-20"
          >
            <div class="mx-auto flex size-12 items-center justify-center rounded-2xl bg-teal-50 text-teal-700">
              <.icon
                name={if(@query != "", do: "hero-magnifying-glass", else: "hero-squares-2x2")}
                class="size-6"
              />
            </div>
            <h3 class="mt-5 text-xl font-semibold tracking-tight text-slate-900">
              <%= cond do %>
                <% @query != "" -> %>
                  No matching models
                <% @mine? -> %>
                  Your library starts here
                <% true -> %>
                  A blank canvas for now
              <% end %>
            </h3>
            <p class="mx-auto mt-2 max-w-sm text-sm leading-relaxed text-slate-500">
              <%= cond do %>
                <% @query != "" -> %>
                  Try a different search or clear the field to see everything.
                <% @mine? -> %>
                  Create a model to keep your questions and assumptions together.
                <% true -> %>
                  Be the first to put a question into a model.
              <% end %>
            </p>
            <button
              :if={@query != ""}
              id="models-empty-clear"
              type="button"
              phx-click="clear_search"
              class="button-secondary mt-6"
            >Clear search</button>
            <.link
              :if={@query == "" && @mine?}
              id="models-empty-new"
              navigate={~p"/models/new"}
              class="button-primary mt-6 inline-flex items-center gap-2"
            >
              <.icon name="hero-plus" class="size-4" /> Create your first model
            </.link>
            <.link
              :if={@query == "" && !@mine?}
              id="models-empty-try"
              navigate={~p"/try"}
              class="button-secondary mt-6 inline-flex items-center gap-2"
            >
              Try a model <.icon name="hero-arrow-right" class="size-4" />
            </.link>
          </div>

          <div
            id="models-grid"
            phx-update="stream"
            class="mt-8 grid gap-5 md:grid-cols-2 xl:grid-cols-3"
          >
            <div
              :for={{id, model} <- @streams.models}
              id={id}
              class="group relative flex min-h-64 flex-col rounded-2xl border border-slate-200 bg-white p-6 shadow-[0_8px_25px_-18px_rgba(15,23,42,0.3)] transition duration-200 hover:-translate-y-0.5 hover:border-teal-200 hover:shadow-[0_18px_35px_-22px_rgba(15,80,75,0.4)]"
            >
              <div class="flex items-center justify-between gap-3">
                <span class="inline-flex items-center gap-1.5 rounded-full bg-slate-100 px-2.5 py-1 text-[11px] font-semibold uppercase tracking-wider text-slate-600">
                  <span class={[
                    "size-1.5 rounded-full",
                    model.visibility == :public && "bg-teal-500",
                    model.visibility == :private && "bg-slate-400",
                    model.visibility == :unlisted && "bg-amber-500"
                  ]}></span>
                  {visibility_label(model.visibility)}
                </span>
                <span class="text-xs text-slate-400">{length(model.metrics || [])} {if length(
                                                                                         model.metrics ||
                                                                                           []
                                                                                       ) == 1,
                                                                                       do: "metric",
                                                                                       else: "metrics"}</span>
              </div>
              <.link
                navigate={~p"/models/#{model.id}"}
                class="mt-7 block rounded-sm focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-teal-600"
              >
                <h3 class="line-clamp-2 text-xl font-semibold tracking-tight text-slate-900 transition group-hover:text-teal-800">
                  {model.title}
                </h3>
              </.link>
              <p class="mt-2 line-clamp-3 flex-1 text-sm leading-relaxed text-slate-500">
                {model.description || "A question worth exploring."}
              </p>
              <div class="mt-7 flex items-center justify-between gap-2 border-t border-slate-100 pt-4">
                <span class="truncate text-xs text-slate-400">
                  {if @mine?, do: "Your model", else: "Community model"}
                </span>
                <button
                  :if={@mine?}
                  id={"delete-model-#{model.id}"}
                  type="button"
                  phx-click="delete"
                  phx-value-id={model.id}
                  data-confirm="Delete this model? This cannot be undone."
                  aria-label={"Delete #{model.title}"}
                  class="relative z-10 flex size-8 shrink-0 items-center justify-center rounded-lg text-slate-400 transition hover:bg-rose-50 hover:text-rose-700 focus-visible:outline-2 focus-visible:outline-rose-600"
                >
                  <.icon name="hero-trash" class="size-4" />
                </button>
                <.icon
                  :if={!@mine?}
                  name="hero-arrow-up-right"
                  class="size-4 shrink-0 text-teal-700 transition group-hover:translate-x-0.5 group-hover:-translate-y-0.5"
                />
              </div>
            </div>
          </div>
        </section>
      </div>
    </Layouts.app>
    """
  end

  defp visibility_label(:public), do: "Public"
  defp visibility_label(:unlisted), do: "Unlisted"
  defp visibility_label(:private), do: "Private"
end
