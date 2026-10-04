defmodule Monty.Accounts.UserNotifierTest do
  use ExUnit.Case, async: true

  alias Monty.Accounts.{User, UserNotifier}

  test "account emails use the Monty sender" do
    user = %User{email: "recipient@example.com"}
    url = "https://monty.sufficient.software/users/log-in/test-token"

    for {notify, recipient} <- [
          {&UserNotifier.deliver_login_instructions/2, user},
          {&UserNotifier.deliver_login_instructions/2,
           %{user | confirmed_at: DateTime.utc_now()}},
          {&UserNotifier.deliver_update_email_instructions/2, user}
        ] do
      assert {:ok, email} = notify.(recipient, url)
      assert email.from == {"Monty", "nick@sufficient.software"}
      assert email.to == [{"", user.email}]
      assert email.text_body =~ url
      assert_receive {:email, ^email}
    end
  end
end
