defmodule Monty.Repo do
  use Ecto.Repo,
    otp_app: :monty,
    adapter: Ecto.Adapters.SQLite3
end
