defmodule AsyncTaskProcessor.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      AsyncTaskProcessorWeb.Telemetry,
      {DNSCluster,
       query: Application.get_env(:async_task_processor, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: AsyncTaskProcessor.PubSub},
      {AsyncTaskProcessor.WorkerPool, []},
      {AsyncTaskProcessor.PoolMonitor, []},
      {AsyncTaskProcessor.QueueManager, []},
      # Start a worker by calling: AsyncTaskProcessor.Worker.start_link(arg)
      # {AsyncTaskProcessor.Worker, arg},
      # Start to serve requests, typically the last entry
      AsyncTaskProcessorWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: AsyncTaskProcessor.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    AsyncTaskProcessorWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
