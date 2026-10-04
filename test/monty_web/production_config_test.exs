defmodule MontyWeb.ProductionConfigTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog
  import Plug.Conn
  import Plug.Test

  setup do
    names = ~w(DATABASE_PATH SECRET_KEY_BASE PHX_HOST POSTMARK_API_KEY)
    previous = Map.new(names, &{&1, System.get_env(&1)})
    on_exit(fn -> System.put_env(previous) end)

    System.put_env("DATABASE_PATH", "/tmp/monty-production-config-test.db")
    System.put_env("SECRET_KEY_BASE", String.duplicate("a", 64))
    System.put_env("POSTMARK_API_KEY", "postmark-test-server-token")
    System.delete_env("PHX_HOST")
    :ok
  end

  test "production uses the custom HTTPS domain and a strict origin allowlist" do
    config = endpoint_config()

    assert config[:url] == [host: "monty.sufficient.software", port: 443, scheme: "https"]
    assert config[:check_origin] == ["https://monty.sufficient.software"]

    for origin <- ["https://monty.sufficient.software", "https://monty.sufficient.software:443"] do
      refute check_origin(origin, config).halted
    end

    for origin <- [
          "http://monty.sufficient.software",
          "https://monty.sufficient.software:444",
          "https://other.monty.sufficient.software",
          "https://monty.sufficient.software.evil.example",
          "https://montie.fly.dev",
          "https://evil.example",
          "null"
        ] do
      capture_log(fn ->
        conn = check_origin(origin, config)
        assert conn.halted
        assert conn.status == 403
      end)
    end
  end

  test "PHX_HOST overrides the URL and allowed origin together" do
    System.put_env("PHX_HOST", "staging.example.com")
    config = endpoint_config()

    assert config[:url] == [host: "staging.example.com", port: 443, scheme: "https"]
    assert config[:check_origin] == ["https://staging.example.com"]
    refute check_origin("https://staging.example.com", config).halted
  end

  test "production sends email through Postmark using the server API token" do
    config =
      Path.expand("../../config/runtime.exs", __DIR__)
      |> Config.Reader.read!(env: :prod, target: :host)
      |> Keyword.fetch!(:monty)
      |> Keyword.fetch!(Monty.Mailer)

    assert config[:adapter] == Swoosh.Adapters.Postmark
    assert config[:api_key] == "postmark-test-server-token"
  end

  test "production requires the Postmark API key" do
    System.delete_env("POSTMARK_API_KEY")

    assert_raise RuntimeError, ~r/environment variable POSTMARK_API_KEY is missing/, fn ->
      Config.Reader.read!(Path.expand("../../config/runtime.exs", __DIR__),
        env: :prod,
        target: :host
      )
    end
  end

  defp endpoint_config do
    Path.expand("../../config/runtime.exs", __DIR__)
    |> Config.Reader.read!(env: :prod, target: :host)
    |> Keyword.fetch!(:monty)
    |> Keyword.fetch!(MontyWeb.Endpoint)
  end

  defp check_origin(origin, config) do
    conn(:get, "/live/websocket")
    |> put_req_header("origin", origin)
    |> Phoenix.Socket.Transport.check_origin(
      Phoenix.LiveView.Socket,
      MontyWeb.Endpoint,
      check_origin: config[:check_origin]
    )
  end
end
