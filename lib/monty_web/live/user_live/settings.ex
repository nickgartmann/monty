defmodule MontyWeb.UserLive.Settings do
  use MontyWeb, :live_view

  on_mount {MontyWeb.UserAuth, :require_sudo_mode}

  alias Monty.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section class="mx-auto max-w-2xl">
        <div class="mb-8">
          <p class="eyebrow mb-3">Your account</p>
          <h1 class="text-3xl font-semibold tracking-tight text-slate-900 sm:text-4xl">
            Account Settings
          </h1>
          <p class="mt-3 text-sm leading-6 text-slate-600">
            Manage how you access Monty. For your security, these changes require a recent sign-in.
          </p>
        </div>

        <div class="space-y-5">
          <section
            aria-labelledby="email-settings-heading"
            class="surface p-6 shadow-[0_18px_55px_-42px_rgba(15,45,49,0.35)] sm:p-8"
          >
            <div class="mb-6">
              <h2 id="email-settings-heading" class="text-lg font-semibold text-slate-900">
                Email address
              </h2>
              <p class="mt-1 text-sm leading-6 text-slate-600">
                We'll send a confirmation link to your new address before changing your account email.
              </p>
            </div>
            <.form
              for={@email_form}
              id="email_form"
              phx-submit="update_email"
              phx-change="validate_email"
            >
              <.input
                field={@email_form[:email]}
                type="email"
                label="Email"
                autocomplete="username"
                spellcheck="false"
                required
              />
              <.button class="button-primary w-full sm:w-auto" phx-disable-with="Changing...">
                Change Email
              </.button>
            </.form>
          </section>

          <section
            aria-labelledby="password-settings-heading"
            class="surface p-6 shadow-[0_18px_55px_-42px_rgba(15,45,49,0.35)] sm:p-8"
          >
            <div class="mb-6">
              <h2 id="password-settings-heading" class="text-lg font-semibold text-slate-900">
                Password
              </h2>
              <p class="mt-1 text-sm leading-6 text-slate-600">
                Set or update a password to log in without waiting for an email link.
              </p>
            </div>
            <.form
              for={@password_form}
              id="password_form"
              action={~p"/users/update-password"}
              method="post"
              phx-change="validate_password"
              phx-submit="update_password"
              phx-trigger-action={@trigger_submit}
            >
              <.input
                field={@password_form[:email]}
                type="hidden"
                id="hidden_user_email"
                value={@current_email}
              />
              <.input
                field={@password_form[:password]}
                type="password"
                label="New password"
                autocomplete="new-password"
                spellcheck="false"
                required
              />
              <.input
                field={@password_form[:password_confirmation]}
                type="password"
                label="Confirm new password"
                autocomplete="new-password"
                spellcheck="false"
              />
              <.button class="button-primary w-full sm:w-auto" phx-disable-with="Saving...">
                Save Password
              </.button>
            </.form>
          </section>
        </div>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    socket =
      case Accounts.update_user_email(socket.assigns.current_scope.user, token) do
        {:ok, _user} ->
          put_flash(socket, :info, "Email changed successfully.")

        {:error, _} ->
          put_flash(socket, :error, "Email change link is invalid or it has expired.")
      end

    {:ok, push_navigate(socket, to: ~p"/users/settings")}
  end

  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    email_changeset = Accounts.change_user_email(user, %{}, validate_unique: false)
    password_changeset = Accounts.change_user_password(user, %{}, hash_password: false)

    socket =
      socket
      |> assign(:current_email, user.email)
      |> assign(:email_form, to_form(email_changeset))
      |> assign(:password_form, to_form(password_changeset))
      |> assign(:trigger_submit, false)

    {:ok, socket}
  end

  @impl true
  def handle_event("validate_email", params, socket) do
    %{"user" => user_params} = params

    email_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_email(user_params, validate_unique: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, email_form: email_form)}
  end

  def handle_event("update_email", params, socket) do
    %{"user" => user_params} = params
    user = socket.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)

    case Accounts.change_user_email(user, user_params) do
      %{valid?: true} = changeset ->
        Accounts.deliver_user_update_email_instructions(
          Ecto.Changeset.apply_action!(changeset, :insert),
          user.email,
          &url(~p"/users/settings/confirm-email/#{&1}")
        )

        info = "A link to confirm your email change has been sent to the new address."
        {:noreply, socket |> put_flash(:info, info)}

      changeset ->
        {:noreply, assign(socket, :email_form, to_form(changeset, action: :insert))}
    end
  end

  def handle_event("validate_password", params, socket) do
    %{"user" => user_params} = params

    password_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_password(user_params, hash_password: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, password_form: password_form)}
  end

  def handle_event("update_password", params, socket) do
    %{"user" => user_params} = params
    user = socket.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)

    case Accounts.change_user_password(user, user_params) do
      %{valid?: true} = changeset ->
        {:noreply, assign(socket, trigger_submit: true, password_form: to_form(changeset))}

      changeset ->
        {:noreply, assign(socket, password_form: to_form(changeset, action: :insert))}
    end
  end
end
