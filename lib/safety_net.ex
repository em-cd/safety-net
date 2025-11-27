defmodule SafetyNet do
  @moduledoc """
  Documentation for `SafetyNet`.
  """

def start() do
    pid = spawn(__MODULE__, :handler, [])
    Process.register(pid, :handler)
    send(:handler, {:init})
    pid
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

  def wait_for_nodes() do
    case Node.list() do
      [] ->
        :timer.sleep(500)
        wait_for_nodes()

      nodes ->
        nodes
    end
  end

end
