defmodule ShipNode do
  @moduledoc """
  Documentation for `SafetyNet`.
  """
use GenServer

defstruct [:id, :data, :peers, :coords]

def start_link(id, peers \\ [], coords \\ {0, 0}) do
  GenServer.start_link(__MODULE__, {id, peers, coords}, name: via(id))
end

defp via(id), do: {:via, Registry, {SafetyNet, id}}

@impl true
def init({id, peers, coords}) do
  state = %__MODULE__{
    id: id,
    data: %{},
    peers: peers,
    coords: coords
  }

  {:ok, state}
end




  def demo_setup() do
    ships = [:A, :B, :C, :D, :E]

    case Registry.start_link(keys: :unique, name: SafetyNet) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    Enum.each(ships, fn node ->
      case Registry.lookup(SafetyNet, node) do
        [{pid, _}] -> GenServer.stop(pid)
        [] -> :ok
      end
    end)

    # Start all nodes with peer connections
    {:ok, _} = ShipNode.start_link(:A, [:B, :C], {1, 1})
    {:ok, _} = ShipNode.start_link(:B, [:A, :C, :D], {0, 4})
    {:ok, _} = ShipNode.start_link(:C, [:A, :B, :E], {8, 3})
    {:ok, _} = ShipNode.start_link(:D, [:B, :E], {3, 7})
    {:ok, _} = ShipNode.start_link(:E, [:C, :D], {2, 5})

    "Network initialized! 5 ships with different initial data."
  end

  def handler() do
    receive do
      {:init} ->
        IO.puts("#{inspect(self())}: received init")
        wait_for_nodes()
        spawn(fn -> ping_scheduler() end)
        handler(Map.new())
    end
  end

  # missing_acks is a map of the form: %{dest_node: ack_requester}
  # where dest_node is the node that we pinged, and ack_requester is the node who should receive
  # an ack. This is either the current node, or another node that requested a ping.
  def handler(missing_acks) do
    IO.puts("#{inspect(self())}: handler, awaiting acks: #{inspect(missing_acks)}")

    receive do
      {:ping, src_node} ->
        IO.puts("#{inspect(self())}: received ping from #{inspect(src_node)}, sending ack")
        send_remote(src_node, :ack)
        handler(missing_acks)

      {:ping_sent, dest_node} ->
        handler(Map.put(missing_acks, dest_node, :me))

      {:ack, src_node} ->
        IO.puts("#{inspect(self())}: received ack from #{inspect(src_node)}")
        ack_requester = Map.fetch(missing_acks, src_node)
        if ack_requester != :me do
          send_remote(ack_requester, :ack, src_node)
        end
        handler(Map.delete(missing_acks, src_node))

      {:ping_request, src_node, node} ->
        send_remote(node, :ping)
        new_missing_acks = Map.put(missing_acks, node, src_node)
        handler(new_missing_acks)
    end
  end

  def ping_scheduler() do
    Enum.each(Enum.shuffle(Node.list()), fn n ->
      IO.puts("#{inspect(self())}: sending ping to #{inspect(n)}")
      send_remote(n, :ping)
      send(:handler, {:ping_sent, n})
      :timer.sleep(5_000)
    end)

    ping_scheduler()
  end

  def send_remote(dest_node, msg_type, src_node \\ Node.self())
  def send_remote(dest_node, msg_type, src_node) do
    send({:handler, dest_node}, {msg_type, src_node})
  end

  def send_ping_requests(node) do
    other_nodes = List.delete(Node.list(), node)
    Enum.each(other_nodes, fn n ->
      send({:handler, n}, {:ping_request, Node.self(), node})
    end)
  end

  defp wait_for_nodes() do
    case Node.list() do
      [] ->
        :timer.sleep(500)
        wait_for_nodes()

      nodes ->
        nodes
    end
  end

end
