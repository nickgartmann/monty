defmodule MontyWeb.UserLive.Confirmation do
  use MontyWeb, :live_view

  alias Monty.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section class="mx-auto max-w-lg">
        <div class="mb-8 text-center">
          <p class="eyebrow mb-3">Secure email link</p>
          <h1 class="text-3xl font-semibold tracking-tight text-slate-900 sm:text-4xl">
            Welcome {@user.email}
          </h1>
          <p class="mt-3 text-sm leading-6 text-slate-600">
            <%= if @user.confirmed_at do %>
              Your email link is ready. Choose how long you'd like to stay logged in.
            <% else %>
              Confirm your email to finish setting up your Monty account.
            <% end %>
          </p>
        </div>

        <div class="surface p-6 shadow-[0_18px_55px_-42px_rgba(15,45,49,0.35)] sm:p-8">
          <p class="mb-5 text-sm leading-6 text-slate-600">
            <%= if @current_scope do %>
              Continue securely with the account linked to this email.
            <% else %>
              Staying logged in is convenient on a device only you use. Choose a one-time session on a shared device.
            <% end %>
          </p>
          <.form
            :if={!@user.confirmed_at}
            for={@form}
            id="confirmation_form"
            phx-mounted={JS.focus_first()}
            phx-submit="submit"
            action={~p"/users/log-in?_action=confirmed"}
            phx-trigger-action={@trigger_submit}
          >
            <.input field={@form[:token]} type="hidden" />
            <div class="space-y-2">
              <.button
                name={@form[:remember_me].name}
                value="true"
                phx-disable-with="Confirming..."
                class="button-primary w-full"
              >
                Confirm and stay logged in
              </.button>
              <.button phx-disable-with="Confirming..." class="button-secondary w-full">
                Confirm and log in only this time
              </.button>
            </div>
          </.form>

          <.form
            :if={@user.confirmed_at}
            for={@form}
            id="login_form"
            phx-submit="submit"
            phx-mounted={JS.focus_first()}
            action={~p"/users/log-in"}
            phx-trigger-action={@trigger_submit}
          >
            <.input field={@form[:token]} type="hidden" />
            <%= if @current_scope do %>
              <.button phx-disable-with="Logging in..." class="button-primary w-full">
                Log in
              </.button>
            <% else %>
              <div class="space-y-2">
                <.button
                  name={@form[:remember_me].name}
                  value="true"
                  phx-disable-with="Logging in..."
                  class="button-primary w-full"
                >
                  Keep me logged in on this device
                </.button>
                <.button phx-disable-with="Logging in..." class="button-secondary w-full">
                  Log me in only this time
                </.button>
              </div>
            <% end %>
          </.form>
        </div>

        <p
          :if={!@user.confirmed_at}
          class="mt-5 rounded-xl border border-teal-100 bg-teal-50/70 px-5 py-4 text-sm leading-6 text-slate-600"
        >
          Prefer a password? You can add one later in your account settings.
        </p>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    if user = Accounts.get_user_by_magic_link_token(token) do
      form = to_form(%{"token" => token}, as: "user")

      {:ok, assign(socket, user: user, form: form, trigger_submit: false),
       temporary_assigns: [form: nil]}
    else
      {:ok,
       socket
       |> put_flash(:error, "Magic link is invalid or it has expired.")
       |> push_navigate(to: ~p"/users/log-in")}
    end
  end

  @impl true
  def handle_event("submit", %{"user" => params}, socket) do
    {:noreply, assign(socket, form: to_form(params, as: "user"), trigger_submit: true)}
  end
end
