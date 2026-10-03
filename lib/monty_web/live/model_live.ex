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
        note_metric: nil,
        note_form: nil,
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
    if id == socket.assigns.selected_id do
      {:noreply, socket}
    else
      case Enum.find(socket.assigns.model.metrics, &(&1["id"] == id)) do
        nil -> {:noreply, socket}
        metric -> {:noreply, socket |> select_metric(metric) |> restream()}
      end
    end
  end

  def handle_event("begin-edit", %{"id" => id, "field" => field}, socket)
      when field in ~w(name input) do
    case Enum.find(socket.assigns.model.metrics, &(&1["id"] == id)) do
      nil ->
        {:noreply, socket}

      metric ->
        {:noreply,
         socket
         |> select_metric(metric)
         |> restream()
         |> push_event("focus-metric-field", %{id: "metric_#{field}"})}
    end
  end

  def handle_event("open-note", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.model.metrics, &(&1["id"] == id)) do
      nil ->
        {:noreply, socket}

      metric ->
        {:noreply,
         assign(socket,
           note_metric: metric,
           note_form: to_form(metric_changeset(%{}, metric), as: :note)
         )}
    end
  end

  def handle_event("close-note", _, socket),
    do: {:noreply, assign(socket, note_metric: nil, note_form: nil)}

  def handle_event("validate-note", %{"note" => params}, socket) do
    if socket.assigns.editable? && socket.assigns.note_metric do
      changeset =
        metric_changeset(Map.take(params, ["notes"]), socket.assigns.note_metric)
        |> Map.put(:action, :validate)

      {:noreply, assign(socket, :note_form, to_form(changeset, as: :note))}
    else
      {:noreply, denied(socket)}
    end
  end

  def handle_event("save-note", %{"note" => params}, socket) do
    note_metric = socket.assigns.note_metric

    metric =
      note_metric && Enum.find(socket.assigns.model.metrics, &(&1["id"] == note_metric["id"]))

    if socket.assigns.editable? && metric do
      changeset =
        metric_changeset(Map.take(params, ["notes"]), metric)
        |> Map.put(:action, :validate)

      if changeset.valid? do
        updated = Map.put(metric, "notes", Ecto.Changeset.get_field(changeset, :notes) || "")

        metrics =
          Enum.map(
            socket.assigns.model.metrics,
            &if(&1["id"] == updated["id"], do: updated, else: &1)
          )

        metric_form = socket.assigns.metric_form

        {:noreply,
         socket
         |> remember()
         |> draft(metrics)
         |> refresh_selection()
         |> assign(metric_form: metric_form, note_metric: nil, note_form: nil)
         |> restream()}
      else
        {:noreply, assign(socket, :note_form, to_form(changeset, as: :note))}
      end
    else
      {:noreply, denied(socket)}
    end
  end

  def handle_event("edit-metric", %{"metric" => params}, socket) do
    edit_metric(socket, params, false)
  end

  def handle_event("save-metric", %{"metric" => params}, socket) do
    edit_metric(socket, params, true)
  end

  def handle_event("add-metric", params, socket) do
    with true <- socket.assigns.editable?,
         true <- length(socket.assigns.model.metrics) < 100,
         {:ok, {x, y}} <- new_metric_position(params, socket.assigns.model.metrics) do
      metrics = socket.assigns.model.metrics
      metric = Examples.metric(next_key(metrics), "New metric", "0", x, y)

      {:noreply,
       socket
       |> remember()
       |> draft(metrics ++ [metric])
       |> select_metric(metric)
       |> restream()}
    else
      {:error, :position} ->
        {:noreply,
         put_flash(socket, :error, "Choose a valid grid point not already used by another card.")}

      _ ->
        {:noreply, put_flash(socket, :error, "You cannot add more metrics to this model.")}
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
         {:ok, x} <- coordinate(x),
         {:ok, y} <- coordinate(y),
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
            socket
            |> assign(dirty?: true, metric_form: to_form(changeset, as: :metric))
            |> restream()
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

    socket
    |> assign(results: results)
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
    assign(socket, selected_id: nil, metric_form: nil)
  end

  defp select_metric(socket, metric) do
    assign(socket,
      selected_id: metric["id"],
      metric_form: to_form(metric_changeset(%{}, metric), as: :metric)
    )
  end

  defp refresh_selection(socket) do
    metric =
      Enum.find(socket.assigns.model.metrics, &(&1["id"] == socket.assigns.selected_id)) ||
        List.first(socket.assigns.model.metrics)

    socket |> select_metric(metric) |> restream()
  end

  defp new_metric_position(params, metrics) do
    case {Map.fetch(params, "x"), Map.fetch(params, "y")} do
      {:error, :error} ->
        {:ok, Canvas.free_position(metrics)}

      {{:ok, x}, {:ok, y}} ->
        with {:ok, x} <- coordinate(x),
             {:ok, y} <- coordinate(y),
             false <- Enum.any?(metrics, &(&1["x"] == x && &1["y"] == y)) do
          {:ok, {x, y}}
        else
          _ -> {:error, :position}
        end

      _ ->
        {:error, :position}
    end
  end

  defp coordinate(value) when is_integer(value) do
    if Canvas.valid_coordinate?(value), do: {:ok, value}, else: :error
  end

  defp coordinate(value) when is_binary(value) do
    case Integer.parse(value) do
      {value, ""} -> coordinate(value)
      _ -> :error
    end
  end

  defp coordinate(_), do: :error

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
    "--metric-left: #{left}px; --metric-top: #{top}px;"
  end

  defp canvas_style do
    dot_offset = rem(Canvas.padding(), Canvas.grid_step()) - div(Canvas.grid_step(), 2)

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
      bend = Canvas.link_bend()

      %{
        source_id: source["id"],
        target_id: target["id"],
        path: "M #{sx} #{sy} C #{sx + bend} #{sy}, #{tx - bend} #{ty}, #{tx} #{ty}"
      }
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

  defp histogram(assigns) do
    bins = Map.get(assigns.result, :histogram, [])
    max_count = Enum.max(bins, fn -> 1 end) |> max(1)
    assigns = assign(assigns, :bars, Enum.map(bins, &max(2, &1 / max_count * 100)))

    ~H"""
    <div
      class="histogram"
      aria-label="Simulated value distribution"
      role="img"
    >
      <span :for={height <- @bars} style={"height: #{height}%"}></span>
    </div>
    """
  end

  attr :type, :string, required: true

  defp distribution_icon(assigns) do
    ~H"""
    <svg
      data-distribution={@type}
      viewBox="0 0 24 18"
      class="distribution-icon"
      fill="none"
      stroke="currentColor"
      stroke-width="1.5"
      stroke-linecap="round"
      stroke-linejoin="round"
      role="img"
      aria-label={"#{String.capitalize(@type)} distribution"}
    >
      <path d="M2 15.5h20" opacity=".35" />
      <%= case @type do %>
        <% "normal" -> %>
          <path d="M2 14.5C6 14.5 7 3 12 3s6 11.5 10 11.5" />
        <% "lognormal" -> %>
          <path d="M2 14.5C3 14.5 3.5 3 6.5 3S10 13.5 22 14.5" />
        <% "uniform" -> %>
          <path d="M2 14.5h3V4h14v10.5h3" />
      <% end %>
    </svg>
    """
  end

  attr :card, :map, required: true
  attr :form, :any, default: nil
  attr :editable?, :boolean, required: true

  defp metric_face(assigns) do
    input = if assigns.form, do: assigns.form[:input].value, else: assigns.card.metric["input"]

    distribution =
      if assigns.form,
        do: assigns.form[:distribution].value,
        else: assigns.card.metric["distribution"]

    distribution =
      if distribution in ~w(normal lognormal uniform),
        do: distribution,
        else: assigns.card.metric["distribution"]

    assigns = assign(assigns, range?: Simulation.range_input?(input), distribution: distribution)

    ~H"""
    <div class="mb-0.5 flex items-center justify-between gap-2">
      <div :if={@form} class="metric-inline-field min-w-0 flex-1">
        <.input
          field={@form[:name]}
          class="metric-inline-input metric-name-input"
          aria-label="Metric name"
          maxlength="120"
          required
          readonly={!@editable?}
        />
      </div>
      <button
        :if={!@form}
        id={"metric-name-#{@card.id}"}
        type="button"
        phx-click="begin-edit"
        phx-value-id={@card.id}
        phx-value-field="name"
        class="metric-edit-trigger min-w-0 truncate text-xs font-semibold leading-4 text-slate-600"
        aria-label={"#{if(@editable?, do: "Edit", else: "View")} name of #{@card.metric["name"]}"}
      >{@card.metric["name"]}</button>
      <div class="flex shrink-0 items-center gap-1">
        <div class="metric-note" data-card-controls>
          <button
            id={"metric-note-#{@card.id}"}
            type="button"
            phx-click="open-note"
            phx-value-id={@card.id}
            class="metric-note-button"
            aria-label={"#{if(@editable?, do: "Edit", else: "View")} note for #{@card.metric["name"]}"}
            aria-describedby={"note-tooltip-#{@card.id}"}
          ><.icon name="hero-document-text" class="size-3.5" /></button>
          <div id={"note-tooltip-#{@card.id}"} class="metric-note-tooltip" role="tooltip">
            <span class="whitespace-pre-wrap">{if(@card.metric["notes"] in [nil, ""],
              do: if(@editable?, do: "Add a note or assumption", else: "No note yet"),
              else: @card.metric["notes"]
            )}</span>
          </div>
        </div>
        <span class="rounded bg-teal-50 px-1.5 font-mono text-[10px] font-semibold leading-4 text-teal-700">
          {@card.metric["key"]}
        </span>
      </div>
    </div>
    <%= if Map.has_key?(@card.result, :error) do %>
      <div
        id={if(@form, do: "metric-error", else: "metric-error-#{@card.id}")}
        class="my-2 flex items-start gap-2 text-[11px] leading-4 text-rose-600"
        role="alert"
      >
        <.icon name="hero-exclamation-circle" class="size-4 shrink-0" />
        <span class="line-clamp-2">{@card.result.error}</span>
      </div>
    <% else %>
      <div
        data-metric-summary
        class="text-[22px] font-semibold leading-6 tracking-tight text-slate-800"
      >
        {format_value(@card.result.mean)}
      </div>
      <div class="mt-0.5"><.histogram result={@card.result} /></div>
      <div class="mt-0.5 flex justify-between font-mono text-[10px] leading-3 text-slate-400">
        <span>{format_value(@card.result.low)}</span><span>{format_value(@card.result.high)}</span>
      </div>
    <% end %>
    <div data-metric-input class="mt-0.5 flex items-center gap-1 border-t border-slate-100 pt-0.5">
      <div :if={@form} class="metric-inline-field min-w-0 flex-1">
        <.input
          field={@form[:input]}
          class="metric-inline-input metric-formula-input"
          aria-label="Estimate or formula"
          required
          maxlength="1000"
          readonly={!@editable?}
        />
      </div>
      <button
        :if={!@form}
        id={"metric-formula-#{@card.id}"}
        type="button"
        phx-click="begin-edit"
        phx-value-id={@card.id}
        phx-value-field="input"
        class="metric-edit-trigger min-w-0 flex-1 truncate text-left font-mono text-[10px] leading-3 text-slate-400"
        aria-label={"#{if(@editable?, do: "Edit", else: "View")} formula for #{@card.metric["name"]}"}
      >{@card.metric["input"]}</button>
      <div :if={@range? && @form && @editable?} class="metric-distribution" data-card-controls>
        <.distribution_icon type={@distribution} />
        <.input
          field={@form[:distribution]}
          type="select"
          class="metric-distribution-select"
          aria-label="Range distribution"
          title={"#{String.capitalize(@distribution)} distribution"}
          options={[
            {"Normal · 90% interval", "normal"},
            {"Lognormal · positive, skewed", "lognormal"},
            {"Uniform · hard bounds", "uniform"}
          ]}
        />
        <.icon name="hero-chevron-down-mini" class="distribution-chevron size-2.5" />
      </div>
      <span :if={@range? && (!@form || !@editable?)} class="metric-distribution-preview">
        <.distribution_icon type={@distribution} />
      </span>
      <.input
        :if={@form && (!@range? || !@editable?)}
        field={@form[:distribution]}
        type="hidden"
        id="metric-distribution-value"
      />
    </div>
    <div
      :if={@form && @form.source.errors != []}
      class="metric-validation"
      data-card-controls
      role="alert"
    >
      <p :for={{field, error} <- @form.source.errors} id={"metric-validation-#{field}"}>
        {Phoenix.Naming.humanize(field)} {translate_error(error)}
      </p>
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
          <span class="hidden text-xs text-slate-400 lg:block">
            Drag background to pan<span :if={@editable?}> · Double-click to add</span>
          </span>
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
          Changes preview immediately; save to keep them. Move cards directly and use the shadow
          to preview where they will snap to the background dots
          ({Canvas.grid_step()}px). Use arrow keys on a focused card to move one dot;
          Shift + arrow moves five dots. Drag the background or scroll to pan in any direction.
          Press Escape to cancel a drag.
          <span class="block text-xs text-teal-700">Simulation estimates are approximate, not guarantees. Normal draws may fall outside the entered interval. Preview uses a fixed seed so edits are comparable.</span>
        </div>

        <div class="model-workspace">
          <section
            id="canvas-viewport"
            class="canvas-scroll"
            style={canvas_style()}
            data-canvas-viewport
            tabindex="0"
            aria-label="Model canvas. Drag background or use arrow keys to pan."
          >
            <div
              id="model-canvas"
              class="canvas-surface"
              data-model-canvas
              data-editable={to_string(@editable?)}
              data-card-width={Canvas.card_width()}
              data-card-height={Canvas.card_height()}
              data-grid-step={Canvas.grid_step()}
              data-grid-padding={Canvas.padding()}
              data-link-bend={Canvas.link_bend()}
            >
              <svg
                class="canvas-connections pointer-events-none absolute left-0 top-0"
                width="1"
                height="1"
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
                  :for={connection <- connections(@model, @results)}
                  id={"connection-#{connection.source_id}-#{connection.target_id}"}
                  data-source-id={connection.source_id}
                  data-target-id={connection.target_id}
                  d={connection.path}
                  class="dependency-path"
                  marker-end="url(#arrowhead)"
                />
              </svg>
              <div id="metrics" phx-update="stream">
                <div
                  :for={{dom_id, card} <- @streams.metrics}
                  id={dom_id}
                  role="group"
                  tabindex="0"
                  phx-click="select"
                  phx-value-id={card.id}
                  data-metric-id={card.id}
                  data-selected={to_string(card.selected?)}
                  data-grid-x={card.metric["x"]}
                  data-grid-y={card.metric["y"]}
                  data-movable={to_string(@editable?)}
                  draggable="false"
                  class={[
                    "metric-card",
                    card.selected? && "metric-card-selected",
                    Map.has_key?(card.result, :error) && "metric-card-error"
                  ]}
                  style={metric_style(card.metric)}
                  aria-label={"#{if(card.selected?, do: "Selected. ", else: "")}#{if(@editable?, do: "Edit", else: "View")} #{card.metric["name"]}, reference #{card.metric["key"]}"}
                >
                  <%= if card.selected? do %>
                    <.form
                      for={@metric_form}
                      id="metric-form"
                      phx-change="edit-metric"
                      phx-submit="save-metric"
                    >
                      <.input type="hidden" id="metric-id" name="metric[id]" value={card.id} />
                      <.metric_face card={card} form={@metric_form} editable?={@editable?} />
                    </.form>
                  <% else %>
                    <.metric_face card={card} editable?={@editable?} />
                  <% end %>
                </div>
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
        </div>
        <div
          :if={@note_metric}
          id="note-modal"
          class="fixed inset-0 z-50 flex items-center justify-center bg-slate-900/30 p-4 backdrop-blur-sm"
          phx-window-keydown="close-note"
          phx-key="Escape"
          phx-mounted={JS.push_focus() |> JS.focus(to: "#note_notes")}
          phx-remove={JS.pop_focus()}
        >
          <.focus_wrap
            id="note-dialog"
            role="dialog"
            aria-modal="true"
            aria-labelledby="note-dialog-title"
            phx-click-away="close-note"
            class="max-h-[90vh] w-full max-w-lg overflow-y-auto rounded-2xl border border-slate-200 bg-white p-6 shadow-xl"
          >
            <div class="mb-5 flex items-start justify-between gap-4">
              <div>
                <p class="eyebrow mb-2">Notes & assumptions · {@note_metric["key"]}</p>
                <h2 id="note-dialog-title" class="text-lg font-semibold text-slate-800">
                  {@note_metric["name"]}
                </h2>
              </div>
              <button
                id="close-note"
                type="button"
                phx-click="close-note"
                class="button-ghost !p-2"
                aria-label="Close note"
              >
                <.icon name="hero-x-mark" class="size-5" />
              </button>
            </div>
            <.form for={@note_form} id="note-form" phx-change="validate-note" phx-submit="save-note">
              <.input
                field={@note_form[:notes]}
                type="textarea"
                label="Note"
                rows="6"
                maxlength="2000"
                readonly={!@editable?}
              />
              <p class="mb-5 text-xs leading-5 text-slate-400">
                Capture your sources, reasoning, or assumptions. Notes do not affect the calculation.
              </p>
              <div class="flex justify-end gap-2">
                <button id="cancel-note" type="button" phx-click="close-note" class="button-secondary">
                  {if(@editable?, do: "Cancel", else: "Close")}
                </button>
                <button
                  :if={@editable?}
                  id="save-note"
                  type="submit"
                  class="button-primary"
                  phx-disable-with="Applying…"
                >
                  Apply note
                </button>
              </div>
            </.form>
          </.focus_wrap>
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
