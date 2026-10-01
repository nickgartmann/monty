defmodule MontyWeb.UserLive.Login do
  use MontyWeb, :live_view

  alias Monty.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section class="mx-auto max-w-lg">
        <div class="mb-8 text-center">
          <p class="eyebrow mb-3">Your account</p>
          <h1 class="text-3xl font-semibold tracking-tight text-slate-900 sm:text-4xl">
            Log in
          </h1>
          <p class="mt-3 text-sm leading-6 text-slate-600">
            <%= if @current_scope do %>
              You need to reauthenticate to perform sensitive actions on your account.
            <% else %>
              Pick up where you left off in Monty.
            <% end %>
          </p>
        </div>

        <div
          :if={local_mail_adapter?()}
          class="mb-5 flex gap-3 rounded-xl border border-teal-200 bg-teal-50 p-4 text-sm leading-6 text-teal-900"
          role="note"
        >
          <.icon name="hero-information-circle" class="mt-0.5 size-5 shrink-0" />
          <p>
            This environment uses a local mail adapter. View sent links in <.link
              href="/dev/mailbox"
              class="font-semibold underline underline-offset-4"
            >the mailbox page</.link>.
          </p>
        </div>

        <div class="surface p-6 shadow-[0_18px_55px_-42px_rgba(15,45,49,0.35)] sm:p-8">
          <div>
            <h2 class="text-base font-semibold text-slate-900">Email link</h2>
            <p class="mt-1 mb-5 text-sm leading-6 text-slate-600">
              Get a one-time link in your inbox. No password needed.
            </p>
            <.form
              for={@form}
              id="login_form_magic"
              action={~p"/users/log-in"}
              phx-submit="submit_magic"
            >
              <.input
                id="login_form_magic_email"
                readonly={!!@current_scope}
                field={@form[:email]}
                type="email"
                label="Email"
                autocomplete="username"
                spellcheck="false"
                required
                phx-mounted={JS.focus()}
              />
              <.button class="button-primary w-full">
                Log in with email <.icon name="hero-arrow-right" class="size-4" />
              </.button>
            </.form>
          </div>

          <div class="my-7 flex items-center gap-4" aria-hidden="true">
            <span class="h-px flex-1 bg-slate-200"></span>
            <span class="text-xs font-medium uppercase tracking-widest text-slate-400">or</span>
            <span class="h-px flex-1 bg-slate-200"></span>
          </div>

          <div>
            <h2 class="text-base font-semibold text-slate-900">Use your password</h2>
            <p class="mt-1 mb-5 text-sm leading-6 text-slate-600">
              If you set a password, you can use it instead of an email link.
            </p>
            <.form
              for={@form}
              id="login_form_password"
              action={~p"/users/log-in"}
              phx-submit="submit_password"
              phx-trigger-action={@trigger_submit}
            >
              <.input
                id="login_form_password_email"
                readonly={!!@current_scope}
                field={@form[:email]}
                type="email"
                label="Email"
                autocomplete="username"
                spellcheck="false"
                required
              />
              <.input
                id="login_form_password_password"
                field={@form[:password]}
                type="password"
                label="Password"
                autocomplete="current-password"
                spellcheck="false"
              />
              <div class="space-y-2">
                <.button class="button-primary w-full" name={@form[:remember_me].name} value="true">
                  Log in and stay logged in <.icon name="hero-arrow-right" class="size-4" />
                </.button>
                <.button class="button-secondary w-full">
                  Log in only this time
                </.button>
              </div>
            </.form>
          </div>
          <p
            :if={!@current_scope}
            class="mt-7 border-t border-slate-100 pt-5 text-center text-sm text-slate-600"
          >
            New to Monty?
            <.link
              navigate={~p"/users/register"}
              class="font-semibold text-teal-700 underline-offset-4 transition-colors hover:text-teal-900 hover:underline"
            >
              Sign up
            </.link>
          </p>
        </div>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    email =
      Phoenix.Flash.get(socket.assigns.flash, :email) ||
        get_in(socket.assigns, [:current_scope, Access.key(:user), Access.key(:email)])

    form = to_form(%{"email" => email}, as: "user")

    {:ok, assign(socket, form: form, trigger_submit: false)}
  end

  @impl true
  def handle_event("submit_password", _params, socket) do
    {:noreply, assign(socket, :trigger_submit, true)}
  end

  def handle_event("submit_magic", %{"user" => %{"email" => email}}, socket) do
    if user = Accounts.get_user_by_email(email) do
      Accounts.deliver_login_instructions(
        user,
        &url(~p"/users/log-in/#{&1}")
      )
    end

    info =
      "If your email is in our system, you will receive instructions for logging in shortly."

    {:noreply,
     socket
     |> put_flash(:info, info)
     |> push_navigate(to: ~p"/users/log-in")}
  end

  defp local_mail_adapter? do
    Application.get_env(:monty, Monty.Mailer)[:adapter] == Swoosh.Adapters.Local
  end
end
