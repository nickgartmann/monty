defmodule MontyWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use MontyWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://phoenix.hexdocs.pm/scopes.html)"

  attr :active, :atom, default: nil
  attr :wide, :boolean, default: false

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header class="app-header">
      <.link
        navigate={~p"/"}
        id="brand"
        class="flex shrink-0 items-center gap-2.5"
        aria-label="Monty home"
      >
        <span class="brand-mark" aria-hidden="true">
          <span></span><span></span><span></span><span></span>
        </span>
        <span class="text-xl font-semibold tracking-tight text-slate-900">monty<span class="text-teal-600">.</span></span>
      </.link>
      <nav class="ml-5 flex items-center gap-1 sm:ml-10" aria-label="Main navigation">
        <.link
          navigate={~p"/explore"}
          id="nav-explore"
          class={["nav-link", @active == :explore && "nav-link-active"]}
        >
          Explore
        </.link>
        <.link
          :if={@current_scope && @current_scope.user}
          navigate={~p"/library"}
          id="nav-library"
          class={["nav-link", @active == :library && "nav-link-active"]}
        >
          My models
        </.link>
      </nav>
      <div class="ml-auto flex items-center gap-2 sm:gap-3">
        <%= if @current_scope && @current_scope.user do %>
          <.link
            href={~p"/users/settings"}
            id="nav-settings"
            class="button-ghost"
            aria-label="Account settings"
          >
            <.icon name="hero-user-circle" class="size-5" />
            <span class="hidden max-w-40 truncate sm:block">{@current_scope.user.email}</span>
          </.link>
          <.link href={~p"/users/log-out"} method="delete" id="nav-logout" class="button-ghost">Log out</.link>
        <% else %>
          <.link navigate={~p"/users/log-in"} id="nav-login" class="button-ghost">Log in</.link>
          <.link navigate={~p"/users/register"} id="nav-register" class="button-primary">Get started</.link>
        <% end %>
      </div>
    </header>

    <main class={[if(@wide, do: "w-full", else: "page-shell max-w-2xl py-12 sm:py-20")]}>
      {render_slot(@inner_block)}
    </main>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end
end
