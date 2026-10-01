defmodule MontyWeb.UserLive.Registration do
  use MontyWeb, :live_view

  alias Monty.Accounts
  alias Monty.Accounts.User

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section class="mx-auto max-w-lg">
        <div class="mb-8 text-center">
          <p class="eyebrow mb-3">Get started</p>
          <h1 class="text-3xl font-semibold tracking-tight text-slate-900 sm:text-4xl">
            Register for an account
          </h1>
          <p class="mt-3 text-sm leading-6 text-slate-600">
            Create your Monty account with an email address. We'll send you a secure link to confirm it.
          </p>
        </div>

        <div class="surface p-6 shadow-[0_18px_55px_-42px_rgba(15,45,49,0.35)] sm:p-8">
          <.form for={@form} id="registration_form" phx-submit="save" phx-change="validate">
            <.input
              field={@form[:email]}
              type="email"
              label="Email"
              autocomplete="username"
              spellcheck="false"
              required
              phx-mounted={JS.focus()}
            />

            <.button phx-disable-with="Creating account..." class="button-primary w-full">
              Create an account <.icon name="hero-arrow-right" class="size-4" />
            </.button>
          </.form>
          <p class="mt-6 border-t border-slate-100 pt-5 text-center text-sm text-slate-600">
            Already registered?
            <.link
              navigate={~p"/users/log-in"}
              class="font-semibold text-teal-700 underline-offset-4 transition-colors hover:text-teal-900 hover:underline"
            >
              Log in
            </.link>
          </p>
        </div>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, %{assigns: %{current_scope: %{user: user}}} = socket)
      when not is_nil(user) do
    {:ok, redirect(socket, to: MontyWeb.UserAuth.signed_in_path(socket))}
  end

  def mount(_params, _session, socket) do
    changeset = Accounts.change_user_email(%User{}, %{}, validate_unique: false)

    {:ok, assign_form(socket, changeset), temporary_assigns: [form: nil]}
  end

  @impl true
  def handle_event("save", %{"user" => user_params}, socket) do
    case Accounts.register_user(user_params) do
      {:ok, user} ->
        {:ok, _} =
          Accounts.deliver_login_instructions(
            user,
            &url(~p"/users/log-in/#{&1}")
          )

        {:noreply,
         socket
         |> put_flash(
           :info,
           "An email was sent to #{user.email}, please access it to confirm your account."
         )
         |> push_navigate(to: ~p"/users/log-in")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset = Accounts.change_user_email(%User{}, user_params, validate_unique: false)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    form = to_form(changeset, as: "user")
    assign(socket, form: form)
  end
end
