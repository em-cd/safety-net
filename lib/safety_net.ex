defmodule SafetyNet do
  @moduledoc """
  Documentation for `SafetyNet`.
  """
  use GenServer

  defstruct [:id, :peers, :coords]

  def start_link(id, peers \\ [], coords \\ {0, 0}) do
    GenServer.start_link(__MODULE__, {id, peers, coords}, name: via(id))
  end

  defp via(id), do: {:via, Registry, {SafetyNet, id}}

  @impl true
  def init({id, peers, coords}) do
    state = %__MODULE__{
      id: id,
      peers: peers,
      coords: coords
    }

    schedule_probe()

    {:ok, state}
  end

  @impl true
  def handle_info(:probe, state) do
    # Pick a random peer and ping them
    if state.peers != [] do
      peer = Enum.random(state.peers)
      GenServer.cast(via(peer), {:ping, state.id, self()})
    end

    # Reschedule the probe
    schedule_probe()

    {:noreply, state}
  end

  @impl true
  def handle_info({:ack, from}, state) do
    IO.puts("#{state.id}: received ack from #{from}")
    {:noreply, state}
  end

  @impl true
  def handle_cast({:ping, from_id, from_pid}, state) do
    IO.puts("#{state.id}: received ping from #{from_id}, sending ack")
    send(from_pid, {:ack, state.id})
    {:noreply, state}
  end

  defp schedule_probe do
    Process.send_after(self(), :probe, 5000)
  end






  # From GenServer-less implementation -------------------------------------------------------------
  # Deleting as I go ^^

  # missing_acks is a map of the form: %{dest_node: ack_requester}
  # where dest_node is the node that we pinged, and ack_requester is the node who should receive
  # an ack. This is either the current node, or another node that requested a ping.
  def handler(missing_acks) do
    IO.puts("#{inspect(self())}: handler, awaiting acks: #{inspect(missing_acks)}")

    receive do
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

end
