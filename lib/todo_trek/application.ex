defmodule TodoTrek.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    :pg.start_link()
    with {:ok, regions_str} <- System.fetch_env("PRIMARY_REGIONS"),
         regions = String.split(regions_str, ","),
         true <- System.fetch_env!("FLY_REGION") in regions do

      :pg.join(:todo_trek_primaries, self())
    end

    children = [
      {DNSCluster, query: Application.get_env(:todo_trek, :dns_cluster_query) || :ignore},
      TodoTrekWeb.Telemetry,
      TodoTrek.Repo,
      TodoTrek.ReplicaRepo,
      {Phoenix.PubSub, name: TodoTrek.PubSub},
      {Finch, name: TodoTrek.Finch},
      TodoTrekWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: TodoTrek.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    TodoTrekWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
