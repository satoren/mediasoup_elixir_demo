defmodule MediasoupElixirDemo.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      MediasoupElixirDemoWeb.Telemetry,
      MediasoupElixirDemoWeb.RouterGroup,
      {DNSCluster,
       query: Application.get_env(:mediasoup_elixir_demo, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: MediasoupElixirDemo.PubSub},
      # Start a worker by calling: MediasoupElixirDemo.Worker.start_link(arg)
      # {MediasoupElixirDemo.Worker, arg},
      MediasoupElixirDemoWeb.UserPresence,
      # Start to serve requests, typically the last entry
      MediasoupElixirDemoWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: MediasoupElixirDemo.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    MediasoupElixirDemoWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
