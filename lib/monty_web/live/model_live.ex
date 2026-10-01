defmodule MontyWeb.ModelLive do
  use MontyWeb, :live_view

  alias Monty.{Canvas, Examples, ModelFile, Models, Simulation}
  alias Monty.Models.Model

  @samples 1000
  @metric_fields %{name: :string, input: :string, distribution: :string, notes: :string}

  @impl true
  def mount(params, _session, socket) do
    socket =
      assign(socket,
        demo?: socket.assigns.live_action == :demo,
        dirty?: false,
        show_settings?: false,
        show_help?: false,
        history: [],
        samples: @samples
      )

    case load_model(socket, params) do
      {:ok, model} ->
        selected = List.first(model.metrics)

        {:ok,
         socket
         |> assign(model: model, selected_id: selected && selected["id"])
         |> assign(:editable?, editable?(socket, model))
         |> assign(:page_title, model.title)
         |> assign(:model_form, to_form(Models.change_model(model)))
         |> recompute()
         |> select_metric(selected)}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "This model is private or no longer available.")
         |> push_navigate(to: ~p"/explore")}
    end
  end

  defp load_model(%{assigns: %{demo?: true}}, _params) do
    {:ok, struct(Model, Examples.demo())}
  end

  defp load_model(socket, %{"id" => id}), do: Models.get_model(socket.assigns.current_scope, id)

  defp editable?(%{assigns: %{demo?: true}}, _model), do: true
  defp editable?(%{assigns: %{current_scope: %{user: %{id: id}}}}, %{user_id: id}), do: true
  defp editable?(_, _), do: false

  @impl true
  def handle_event("select", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.model.metrics, &(&1["id"] == id)) do
      nil -> {:noreply, socket}
      metric -> {:noreply, socket |> select_metric(metric) |> restream()}
    end
  end

  def handle_event("edit-metric", %{"metric" => params}, socket) do
    edit_metric(socket, params, false)
  end

  def handle_event("save-metric", %{"metric" => params}, socket) do
    edit_metric(socket, params, true)
  end

  def handle_event("add-metric", _params, socket) do
    with true <- socket.assigns.editable?,
         true <- length(socket.assigns.model.metrics) < 100 do
      metrics = socket.assigns.model.metrics
      {x, y} = Canvas.free_position(metrics)
      metric = Examples.metric(next_key(metrics), "New metric", "0", x, y)

      {:noreply,
       socket
       |> remember()
       |> draft(metrics ++ [metric])
       |> select_metric(metric)
       |> restream()}
    else
      _ -> {:noreply, put_flash(socket, :error, "You cannot add more metrics to this model.")}
    end
  end

  def handle_event("delete-metric", %{"id" => id}, socket) do
    if socket.assigns.editable? do
      metrics = Enum.reject(socket.assigns.model.metrics, &(&1["id"] == id))

      {:noreply,
       socket
       |> remember()
       |> draft(metrics)
       |> select_metric(List.first(metrics))
       |> restream()}
    else
      {:noreply, denied(socket)}
    end
  end

  def handle_event("move-metric", %{"id" => id, "x" => x, "y" => y}, socket) do
    with true <- socket.assigns.editable?,
         metric when not is_nil(metric) <-
           Enum.find(socket.assigns.model.metrics, &(&1["id"] == id)),
         {:ok, x} <- coordinate(x, Canvas.max_x()),
         {:ok, y} <- coordinate(y, Canvas.max_y()),
         false <-
           Enum.any?(
             socket.assigns.model.metrics,
             &(&1["id"] != id && &1["x"] == x && &1["y"] == y)
           ) do
      if {metric["x"], metric["y"]} == {x, y} do
        {:noreply, socket}
      else
        metrics =
          Enum.map(socket.assigns.model.metrics, fn
            %{"id" => ^id} = metric -> Map.merge(metric, %{"x" => x, "y" => y})
            metric -> metric
          end)

        {:noreply, socket |> remember() |> draft(metrics) |> refresh_selection()}
      end
    else
      _ ->
        {:noreply,
         put_flash(socket, :error, "Choose a valid grid point not already used by another card.")}
    end
  end

  def handle_event("save", _params, socket), do: {:noreply, save(socket)}

  def handle_event("undo", _params, socket) do
    case {socket.assigns.editable?, socket.assigns.history} do
      {true, [metrics | history]} ->
        {:noreply, socket |> assign(:history, history) |> draft(metrics) |> refresh_selection()}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("resample", _params, socket),
    do: {:noreply, socket |> recompute() |> refresh_selection()}

  def handle_event("toggle-settings", _, socket),
    do: {:noreply, assign(socket, :show_settings?, !socket.assigns.show_settings?)}

  def handle_event("toggle-help", _, socket),
    do: {:noreply, assign(socket, :show_help?, !socket.assigns.show_help?)}

  def handle_event("save-settings", %{"model" => params}, socket) do
    if socket.assigns.editable? do
      changeset =
        Models.change_model(
          socket.assigns.model,
          Map.take(params, ~w(title description visibility))
        )

      case Ecto.Changeset.apply_action(changeset, :update) do
        {:ok, model} ->
          {:noreply,
           socket
           |> assign(model: model, dirty?: true, show_settings?: false)
           |> assign(:page_title, model.title)
           |> save()}

        {:error, changeset} ->
          {:noreply, assign(socket, :model_form, to_form(changeset))}
      end
    else
      {:noreply, denied(socket)}
    end
  end

  def handle_event("duplicate", _, socket) do
    if socket.assigns.current_scope do
      result =
        if socket.assigns.demo? do
          Models.create_model(socket.assigns.current_scope, %{
            title: socket.assigns.model.title,
            description: socket.assigns.model.description,
            visibility: :private,
            metrics: socket.assigns.model.metrics
          })
        else
          Models.duplicate_model(socket.assigns.current_scope, socket.assigns.model)
        end

      case result do
        {:ok, model} -> {:noreply, push_navigate(socket, to: ~p"/models/#{model.id}")}
        _ -> {:noreply, put_flash(socket, :error, "This model could not be copied.")}
      end
    else
      {:noreply, push_navigate(socket, to: ~p"/users/register")}
    end
  end

  def handle_event("export", _, socket) do
    case ModelFile.encode(socket.assigns.model) do
      {:ok, content} ->
        {:noreply,
         push_event(socket, "download-model", %{name: "monty-model.json", content: content})}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, error)}
    end
  end

  defp edit_metric(socket, params, save?) do
    metric = Enum.find(socket.assigns.model.metrics, &(&1["id"] == params["id"]))

    if socket.assigns.editable? && metric do
      changeset = metric_changeset(params, metric) |> Map.put(:action, :validate)

      if changeset.valid? do
        values =
          Ecto.Changeset.apply_changes(changeset)
          |> Map.new(fn {key, value} -> {Atom.to_string(key), value} end)

        updated = Map.merge(metric, values)

        metrics =
          Enum.map(
            socket.assigns.model.metrics,
            &if(&1["id"] == updated["id"], do: updated, else: &1)
          )

        socket =
          socket
          |> remember()
          |> draft(metrics)
          |> refresh_selection()

        {:noreply, if(save? && !socket.assigns.demo?, do: save(socket), else: socket)}
      else
        socket =
          if metric["id"] == socket.assigns.selected_id do
            assign(socket, dirty?: true, metric_form: to_form(changeset, as: :metric))
          else
            socket
          end

        {:noreply, socket}
      end
    else
      {:noreply, denied(socket)}
    end
  end

  defp metric_changeset(params, metric) do
    data = Map.new(Map.keys(@metric_fields), &{&1, Map.get(metric, Atom.to_string(&1))})

    {data, @metric_fields}
    |> Ecto.Changeset.cast(params, Map.keys(@metric_fields))
    |> Ecto.Changeset.validate_required([:name, :input, :distribution])
    |> Ecto.Changeset.validate_length(:name, max: 120)
    |> Ecto.Changeset.validate_length(:input, max: 1000)
    |> Ecto.Changeset.validate_length(:notes, max: 2000)
    |> Ecto.Changeset.validate_inclusion(:distribution, ~w(normal lognormal uniform))
  end

  defp denied(socket),
    do: put_flash(socket, :error, "Only the owner can edit this model. Make a copy to explore.")

  defp save(
         %{assigns: %{metric_form: %Phoenix.HTML.Form{source: %Ecto.Changeset{valid?: false}}}} =
           socket
       ) do
    put_flash(socket, :error, "Fix the selected metric's fields before saving.")
  end

  defp save(%{assigns: %{demo?: true}} = socket) do
    put_flash(
      socket,
      :info,
      "This is a sandbox. Use “Save a copy” to keep your model in your account."
    )
  end

  defp save(%{assigns: %{editable?: false}} = socket), do: denied(socket)

  defp save(socket) do
    model = socket.assigns.model

    case Models.update_model(socket.assigns.current_scope, model, %{
           title: model.title,
           description: model.description,
           visibility: model.visibility,
           metrics: model.metrics
         }) do
      {:ok, model} ->
        socket
        |> assign(model: model, dirty?: false)
        |> assign(:model_form, to_form(Models.change_model(model)))
        |> put_flash(:info, "Model saved.")

      {:error, :stale} ->
        put_flash(
          socket,
          :error,
          "This model changed in another session. Reload before saving; export your draft to keep it."
        )

      {:error, %Ecto.Changeset{} = changeset} ->
        assign(socket, :model_form, to_form(changeset))
        |> put_flash(:error, "Your model could not be saved. Check its fields.")

      _ ->
        denied(socket)
    end
  end

  defp remember(socket) do
    assign(
      socket,
      :history,
      Enum.take([socket.assigns.model.metrics | socket.assigns.history], 20)
    )
  end

  defp draft(socket, metrics) do
    socket
    |> assign(model: %{socket.assigns.model | metrics: metrics}, dirty?: true)
    |> recompute()
  end

  defp recompute(socket) do
    results = Simulation.run(socket.assigns.model.metrics, samples: @samples, seed: {41, 72, 19})
    {width, height} = Canvas.size(socket.assigns.model.metrics)

    socket
    |> assign(results: results, canvas_width: width, canvas_height: height)
    |> restream()
  end

  defp restream(socket) do
    cards =
      Enum.map(socket.assigns.model.metrics, fn metric ->
        %{
          id: metric["id"],
          metric: metric,
          result:
            Map.get(socket.assigns.results, metric["key"], %{error: "No result", dependencies: []}),
          selected?: metric["id"] == socket.assigns.selected_id
        }
      end)

    # Update existing nodes in place: resetting the stream loses a card's keyboard
    # focus on every nudge. Only remove cards that actually left the model.
    ids = MapSet.new(cards, & &1.id)
    previous_ids = Map.get(socket.assigns, :metric_ids, MapSet.new())

    socket =
      Enum.reduce(MapSet.difference(previous_ids, ids), socket, fn id, socket ->
        stream_delete(socket, :metrics, %{id: id})
      end)

    socket
    |> stream(:metrics, cards)
    |> assign(:metric_ids, ids)
  end

  defp select_metric(socket, nil) do
    assign(socket, selected: nil, selected_id: nil, selected_result: nil, metric_form: nil)
  end

  defp select_metric(socket, metric) do
    assign(socket,
      selected: metric,
      selected_id: metric["id"],
      selected_result: Map.get(socket.assigns.results, metric["key"]),
      metric_form: to_form(metric_changeset(%{}, metric), as: :metric)
    )
  end

  defp refresh_selection(socket) do
    metric =
      Enum.find(socket.assigns.model.metrics, &(&1["id"] == socket.assigns.selected_id)) ||
        List.first(socket.assigns.model.metrics)

    socket |> select_metric(metric) |> restream()
  end

  defp coordinate(value, max) when is_integer(value) and value >= 0 and value <= max,
    do: {:ok, value}

  defp coordinate(value, max) when is_binary(value) do
    case Integer.parse(value) do
      {value, ""} -> coordinate(value, max)
      _ -> :error
    end
  end

  defp coordinate(_, _), do: :error

  defp next_key(metrics) do
    # Do not reuse a deleted reference while a formula still names it.
    references =
      Enum.flat_map(metrics, &(Regex.scan(~r/\b[A-Z]{1,4}\b/, &1["input"]) |> List.flatten()))

    keys = MapSet.new(Enum.map(metrics, & &1["key"]) ++ references)

    Enum.find_value(0..701, fn index ->
      key =
        if index < 26,
          do: <<?A + index>>,
          else: <<?A + div(index - 26, 26)>> <> <<?A + rem(index - 26, 26)>>

      if !MapSet.member?(keys, key), do: key
    end)
  end

  defp metric_style(metric) do
    {left, top} = Canvas.pixel_position(metric)
    "left: #{left}px; top: #{top}px;"
  end

  defp canvas_style(width, height) do
    dot_offset = rem(Canvas.padding(), Canvas.grid_step()) - div(Canvas.grid_step(), 2)

    "width: #{width}px; height: #{height}px; " <>
      "--canvas-grid-step: #{Canvas.grid_step()}px; --canvas-dot-offset: #{dot_offset}px; " <>
      "--metric-width: #{Canvas.card_width()}px; --metric-height: #{Canvas.card_height()}px;"
  end

  defp connections(model, results) do
    by_key = Map.new(model.metrics, &{&1["key"], &1})

    for target <- model.metrics,
        dependency <- Map.get(Map.get(results, target["key"], %{}), :dependencies, []),
        source = Map.get(by_key, dependency),
        source do
      {source_left, source_top} = Canvas.pixel_position(source)
      {target_left, target_top} = Canvas.pixel_position(target)
      sx = source_left + Canvas.card_width()
      sy = source_top + div(Canvas.card_height(), 2)
      tx = target_left
      ty = target_top + div(Canvas.card_height(), 2)
      "M #{sx} #{sy} C #{sx + 50} #{sy}, #{tx - 50} #{ty}, #{tx} #{ty}"
    end
  end

  defp format_value(nil), do: "—"

  defp format_value(value) when abs(value) >= 1_000_000,
    do: "#{Float.round(value / 1_000_000, 2)}m"

  defp format_value(value) when abs(value) >= 1000, do: "#{Float.round(value / 1000, 2)}k"

  defp format_value(value) when abs(value) < 0.01 and value != 0,
    do: :erlang.float_to_binary(value * 1.0, [:compact, scientific: 2])

  defp format_value(value), do: value |> Kernel.*(1.0) |> Float.round(2) |> Float.to_string()

  attr :result, :map, required: true
  attr :large, :boolean, default: false

  defp histogram(assigns) do
    bins = Map.get(assigns.result, :histogram, [])
    max_count = Enum.max(bins, fn -> 1 end) |> max(1)
    assigns = assign(assigns, :bars, Enum.map(bins, &max(2, &1 / max_count * 100)))

    ~H"""
    <div
      class={["histogram", @large && "histogram-lg"]}
      aria-label="Simulated value distribution"
      role="img"
    >
      <span :for={height <- @bars} style={"height: #{height}%"}></span>
    </div>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} wide active={:library}>
      <div id="model-page">
        <div class="flex flex-wrap items-start justify-between gap-4 border-b border-slate-200/70 bg-white px-6 py-5 sm:px-8">
          <div class="min-w-0">
            <div class="mb-2 flex items-center gap-2 text-xs text-slate-400">
              <.link navigate={~p"/explore"} class="hover:text-teal-700">Models</.link>
              <.icon name="hero-chevron-right-mini" class="size-3" />
              <span :if={@demo?} class="text-teal-600">Interactive sandbox</span>
              <span :if={!@demo?} class="capitalize">{@model.visibility} model</span>
            </div>
            <h1 id="model-title" class="text-xl font-semibold tracking-tight text-slate-800">
              {@model.title}
            </h1>
            <p class="mt-1 max-w-2xl text-xs leading-relaxed text-slate-500">{@model.description}</p>
          </div>
          <div class="flex flex-wrap items-center gap-2">
            <span
              id="save-status"
              class="mr-2 flex items-center gap-1.5 text-xs text-slate-400"
              role="status"
            >
              <span class={[
                "size-1.5 rounded-full",
                if(@dirty?, do: "bg-amber-400", else: "bg-teal-500")
              ]}></span>
              <%= cond do %>
                <% @demo? -> %>
                  Not saved · sandbox
                <% @dirty? -> %>
                  Unsaved changes
                <% true -> %>
                  All changes saved
              <% end %>
            </span>
            <button
              id="export-model"
              phx-click="export"
              class="button-secondary"
              aria-label="Export model as JSON"
            >
              <.icon name="hero-arrow-down-tray" class="size-4" /><span class="hidden sm:block">Export</span>
            </button>
            <button
              :if={@editable? && !@demo?}
              id="model-settings"
              phx-click="toggle-settings"
              class="button-secondary"
            >
              <.icon name="hero-adjustments-horizontal" class="size-4" /><span class="hidden sm:block">Settings</span>
            </button>
            <button
              :if={@editable? && !@demo?}
              id="save-model"
              phx-click="save"
              class="button-primary"
              phx-disable-with="Saving…"
              disabled={@metric_form && !@metric_form.source.valid?}
            >
              <.icon name="hero-check" class="size-4" />Save model
            </button>
            <button
              id="duplicate-model"
              phx-click="duplicate"
              class={if(@editable? && !@demo?, do: "button-secondary", else: "button-primary")}
            >
              <.icon name="hero-document-duplicate" class="size-4" />{if(@editable? && !@demo?,
                do: "Duplicate saved model",
                else: "Save a copy"
              )}
            </button>
          </div>
        </div>

        <div
          :if={@show_settings? && @editable?}
          id="model-settings-panel"
          class="border-b border-teal-100 bg-teal-50/40 px-6 py-6"
        >
          <.form
            for={@model_form}
            id="model-settings-form"
            phx-submit="save-settings"
            class="mx-auto max-w-3xl"
          >
            <div class="grid gap-x-6 sm:grid-cols-2">
              <.input field={@model_form[:title]} label="Model title" maxlength="120" required />
              <.input
                field={@model_form[:visibility]}
                type="select"
                label="Who can see this?"
                options={[
                  {"Private · only you", :private},
                  {"Unlisted · anyone with the link", :unlisted},
                  {"Public · listed in Explore", :public}
                ]}
              />
            </div>
            <.input
              field={@model_form[:description]}
              type="textarea"
              label="Description"
              rows="2"
              maxlength="2000"
            />
            <p class="mb-4 text-xs text-slate-500">
              Unlisted links are not secret tokens. Anyone with the URL can read the model; use Private for sensitive information.
            </p>
            <div class="flex items-center gap-3">
              <button id="save-settings" class="button-primary" type="submit">Save settings</button>
              <button type="button" class="button-ghost" phx-click="toggle-settings">Cancel</button>
              <.link
                :if={@model.visibility != :private && @model.id}
                href={~p"/models/#{@model.id}"}
                class="ml-auto text-xs text-teal-700"
              >Share this URL</.link>
            </div>
          </.form>
        </div>

        <div class="flex flex-wrap items-center gap-2 border-b border-slate-200/70 bg-white px-6 py-2.5 sm:px-8">
          <button :if={@editable?} id="add-metric" phx-click="add-metric" class="button-secondary">
            <.icon name="hero-plus" class="size-4" />Add metric
          </button>
          <button
            :if={@editable?}
            id="undo"
            phx-click="undo"
            class="button-ghost"
            disabled={@history == []}
            aria-label="Undo last metric change"
          >
            <.icon name="hero-arrow-uturn-left" class="size-4" />
          </button>
          <span class="ml-2 hidden text-xs text-slate-400 sm:block">{length(@model.metrics)} metrics · {@samples} correlated draws</span>
          <div class="ml-auto flex items-center gap-2">
            <button id="resample" phx-click="resample" class="button-ghost"><.icon
              name="hero-arrow-path"
              class="size-4"
            />Recalculate</button>
            <button
              id="formula-help"
              phx-click="toggle-help"
              class="button-ghost"
              aria-expanded={to_string(@show_help?)}
            ><.icon name="hero-question-mark-circle" class="size-4" />Guide</button>
          </div>
        </div>
        <div
          :if={@show_help?}
          id="formula-guide"
          class="border-b border-teal-100 bg-teal-50 px-8 py-5 text-sm leading-7 text-teal-900"
        >
          <strong>A spreadsheet for things you don't know.</strong>
          Enter a number (<code>42</code>), a range (<code>10 to 20</code>), or a formula (<code>=A * B</code>).
          Normal and lognormal ranges describe a 90% interval; uniform ranges are hard bounds.
          <span id="distribution-guide" class="block">
            For explicit distributions, use <code>=normal(100, 15)</code>
            (mean, standard deviation), <code>=lognormal(0, 1)</code>
            (mean and standard deviation in log space), or <code>=uniform(10, 20)</code>
            (hard bounds). Parameters can reference cards, like <code>=normal(A, B)</code>.
            The range selector applies only to <code>lower to upper</code>
            inputs.
          </span>
          <span id="pert-guide" class="block">
            For a bounded estimate with a most likely value, use <code>=pert(10, 15, 30)</code>
            (minimum, mode, maximum). PERT uses a smooth beta distribution with weighting 4;
            the minimum must be less than the maximum, and the mode must lie between them.
            Metric references work too: <code>=pert(A, B, C)</code>.
          </span>
          References use the permanent letter on each card. Arithmetic, parentheses, <code>min</code>, <code>max</code>, <code>abs</code>, <code>sqrt</code>, <code>log</code>, <code>exp</code>, <code>sum</code>, and
          <code>mean</code>
          are supported, along with <code>sin</code>, <code>cos</code>, <code>tan</code>, <code>floor</code>, <code>ceil</code>, and <code>round</code>.
          Changes preview immediately; save to keep them. Drag cards to snap to the background dots
          ({Canvas.grid_step()}px). Use the position controls or arrow keys on a focused card to move one dot;
          Shift + arrow moves five dots.
          <span class="block text-xs text-teal-700">Simulation estimates are approximate, not guarantees. Normal draws may fall outside the entered interval. Preview uses a fixed seed so edits are comparable.</span>
        </div>

        <div class="model-workspace">
          <section class="canvas-scroll" aria-label="Model canvas">
            <div
              id="model-canvas"
              class="canvas-surface relative"
              style={canvas_style(@canvas_width, @canvas_height)}
              data-model-canvas
              data-grid-step={Canvas.grid_step()}
              data-grid-padding={Canvas.padding()}
              data-grid-max-x={Canvas.max_x()}
              data-grid-max-y={Canvas.max_y()}
            >
              <svg
                class="pointer-events-none absolute inset-0"
                width={@canvas_width}
                height={@canvas_height}
                aria-hidden="true"
              >
                <defs>
                  <marker
                    id="arrowhead"
                    markerWidth="6"
                    markerHeight="6"
                    refX="5"
                    refY="3"
                    orient="auto"
                  >
                    <path d="M0,0 L6,3 L0,6" fill="#a7c7b8" />
                  </marker>
                </defs>
                <path
                  :for={path <- connections(@model, @results)}
                  d={path}
                  class="dependency-path"
                  marker-end="url(#arrowhead)"
                />
              </svg>
              <div id="metrics" phx-update="stream">
                <button
                  :for={{dom_id, card} <- @streams.metrics}
                  id={dom_id}
                  type="button"
                  phx-click="select"
                  phx-value-id={card.id}
                  data-metric-id={card.id}
                  data-grid-x={card.metric["x"]}
                  data-grid-y={card.metric["y"]}
                  draggable={to_string(@editable?)}
                  class={[
                    "metric-card",
                    card.selected? && "metric-card-selected",
                    Map.has_key?(card.result, :error) && "metric-card-error"
                  ]}
                  style={metric_style(card.metric)}
                  aria-pressed={to_string(card.selected?)}
                  aria-label={"Edit #{card.metric["name"]}, reference #{card.metric["key"]}"}
                >
                  <div class="mb-3 flex items-center justify-between gap-2">
                    <span class="truncate text-xs font-semibold text-slate-600">{card.metric["name"]}</span>
                    <span class="rounded bg-teal-50 px-1.5 py-0.5 font-mono text-[10px] font-semibold text-teal-700">{card.metric[
                      "key"
                    ]}</span>
                  </div>
                  <%= if Map.has_key?(card.result, :error) do %>
                    <div class="my-5 flex items-center gap-2 text-xs leading-5 text-rose-600">
                      <.icon name="hero-exclamation-circle" class="size-5 shrink-0" />{card.result.error}
                    </div>
                  <% else %>
                    <div class="flex items-baseline gap-2">
                      <span class="text-2xl font-semibold tracking-tight text-slate-800">{format_value(
                        card.result.mean
                      )}</span><span class="text-[10px] text-slate-400">mean</span>
                    </div>
                    <div class="mt-3"><.histogram result={card.result} /></div>
                    <div class="mt-2 flex justify-between font-mono text-[10px] text-slate-400">
                      <span>{format_value(card.result.low)}</span><span>{format_value(
                        card.result.high
                      )}</span>
                    </div>
                  <% end %>
                  <div class="mt-2 truncate border-t border-slate-100 pt-2 font-mono text-[10px] text-slate-400">
                    {card.metric["input"]}
                  </div>
                </button>
              </div>
              <div
                :if={@model.metrics == []}
                id="empty-canvas"
                class="absolute left-12 top-16 max-w-xs rounded-xl border border-dashed border-teal-200 bg-white/90 p-8"
              >
                <.icon name="hero-squares-plus" class="mb-4 size-8 text-teal-600" />
                <h2 class="font-semibold">Start with one thing you know.</h2>
                <p class="mt-2 text-sm leading-6 text-slate-500">
                  Add a metric, give it a range, and build from there.
                </p>
              </div>
            </div>
          </section>

          <aside id="metric-detail" class="metric-detail" aria-label="Selected metric details">
            <%= if @selected do %>
              <div class="mb-6 flex items-center justify-between">
                <p class="eyebrow">Metric details</p>
                <span class="rounded-md bg-teal-50 px-2 py-1 font-mono text-xs font-semibold text-teal-700">{@selected[
                  "key"
                ]}</span>
              </div>
              <.form
                for={@metric_form}
                id="metric-form"
                phx-change="edit-metric"
                phx-submit="save-metric"
              >
                <.input type="hidden" id="metric-id" name="metric[id]" value={@selected["id"]} />
                <.input
                  field={@metric_form[:name]}
                  label="Name"
                  maxlength="120"
                  required
                  readonly={!@editable?}
                />
                <.input
                  field={@metric_form[:input]}
                  label="Estimate or formula"
                  class="form-input font-mono text-sm"
                  required
                  maxlength="1000"
                  readonly={!@editable?}
                />
                <p id="estimate-help" class="-mt-2 mb-5 text-[11px] leading-5 text-slate-400">
                  Try <code>10 to 20</code>, <code>5%</code>, <code>=A * B</code>,
                  or <code>=pert(10, 15, 30)</code>.
                </p>
                <.input
                  field={@metric_form[:distribution]}
                  type="select"
                  label="Range distribution"
                  options={[
                    {"Normal · 90% interval", "normal"},
                    {"Lognormal · positive, skewed", "lognormal"},
                    {"Uniform · hard bounds", "uniform"}
                  ]}
                  disabled={!@editable?}
                />
                <p
                  id="range-distribution-help"
                  class="-mt-2 mb-5 text-[11px] leading-5 text-slate-400"
                >
                  Applies only to ranges like <code>10 to 20</code>.
                  Distribution calls in formulas use their own parameters.
                </p>
                <.input
                  field={@metric_form[:notes]}
                  label="Notes & assumptions"
                  type="textarea"
                  rows="2"
                  maxlength="2000"
                  readonly={!@editable?}
                />
                <button :if={@editable?} id="apply-metric" type="submit" class="button-primary w-full">{if(
                  @demo?,
                  do: "Apply changes",
                  else: "Apply & save changes"
                )}<.icon
                  name="hero-arrow-right"
                  class="size-4"
                /></button>
              </.form>
              <p
                :if={!@editable?}
                class="mb-6 rounded-lg bg-slate-50 p-3 text-xs leading-5 text-slate-500"
              >
                You're viewing a shared model. Save a copy to change its assumptions.
              </p>
              <div
                :if={@selected_result && !Map.has_key?(@selected_result, :error)}
                id="metric-statistics"
                class="mt-7 border-t border-slate-100 pt-6"
              >
                <div class="mb-5 flex justify-between">
                  <p class="eyebrow">Possible outcomes</p><span class="text-[10px] text-slate-400">90% interval</span>
                </div>
                <.histogram result={@selected_result} large />
                <div class="mt-5 grid grid-cols-3 gap-2">
                  <div>
                    <p class="stat-label">5th %ile</p><p id="stat-low" class="stat-value">
                      {format_value(@selected_result.low)}
                    </p>
                  </div>
                  <div>
                    <p class="stat-label">Median</p><p id="stat-median" class="stat-value">
                      {format_value(@selected_result.median)}
                    </p>
                  </div>
                  <div>
                    <p class="stat-label">95th %ile</p><p id="stat-high" class="stat-value">
                      {format_value(@selected_result.high)}
                    </p>
                  </div>
                </div>
              </div>
              <p
                :if={@selected_result && Map.has_key?(@selected_result, :error)}
                id="metric-error"
                class="mt-4 rounded-lg bg-rose-50 p-3 text-xs leading-5 text-rose-600"
                role="alert"
              >
                {@selected_result.error}
              </p>
              <div :if={@editable?} class="mt-7 border-t border-slate-100 pt-5">
                <p class="eyebrow mb-3">Canvas position</p>
                <p class="mb-3 text-[11px] text-slate-400">
                  Snap to dots · {Canvas.grid_step()}px per step
                </p>
                <div class="flex items-center justify-between">
                  <div class="flex gap-1">
                    <button
                      :for={
                        {direction, dx, dy, icon} <- [
                          {"left", -1, 0, "hero-arrow-left-mini"},
                          {"up", 0, -1, "hero-arrow-up-mini"},
                          {"down", 0, 1, "hero-arrow-down-mini"},
                          {"right", 1, 0, "hero-arrow-right-mini"}
                        ]
                      }
                      type="button"
                      id={"move-#{direction}"}
                      class="button-secondary px-2"
                      phx-click="move-metric"
                      phx-value-id={@selected["id"]}
                      phx-value-x={@selected["x"] + dx}
                      phx-value-y={@selected["y"] + dy}
                      aria-label={"Move metric #{direction} #{Canvas.grid_step()} pixels"}
                    >
                      <.icon name={icon} class="size-3.5" />
                    </button>
                  </div>
                  <button
                    id="delete-metric"
                    type="button"
                    class="button-ghost !text-rose-500"
                    phx-click="delete-metric"
                    phx-value-id={@selected["id"]}
                    data-confirm="Delete this metric? Formulas that reference it will need updating."
                    aria-label="Delete selected metric"
                  ><.icon name="hero-trash" class="size-4" /></button>
                </div>
              </div>
            <% else %>
              <p class="eyebrow">Metric details</p>
              <p class="mt-5 text-sm leading-6 text-slate-400">
                Select a card to edit its assumptions and explore the distribution.
              </p>
            <% end %>
            <div class="mt-8 flex items-center gap-2 text-[10px] text-slate-400">
              <.icon name="hero-beaker" class="size-3.5" />Monte Carlo, not a crystal ball.
            </div>
          </aside>
        </div>
        <div
          id="model-interactions"
          phx-hook="ModelInteractions"
          phx-update="ignore"
          data-canvas-id="model-canvas"
        >
        </div>
      </div>
    </Layouts.app>
    """
  end
end
