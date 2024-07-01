defmodule TodoTrek.RPC do
  use GenServer

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def primary?, do: :persistent_term.get({__MODULE__, :primary?})

  def rpc_primary(func) when is_function(func, 0) do
    primary = primary?()
    members = !primary && :pg.get_members({__MODULE__, :primaries})

    if primary || members == [] do
      func.()
    else
      :erpc.call(node(Enum.random(members)), func)
    end
  end

  def init(_) do
    {:ok, pg} = :pg.start_link()

    self_primary? =
      case System.fetch_env("PRIMARY_REGIONS") do
        {:ok, regions} -> System.fetch_env!("FLY_REGION") in String.split(regions, ",")
        :error -> true
      end

    :persistent_term.put({__MODULE__, :primary?}, self_primary?)
    if self_primary?, do: :pg.join({__MODULE__, :primaries}, self())

    {:ok, %{pg: pg, primary?: self_primary?}}
  end
end
