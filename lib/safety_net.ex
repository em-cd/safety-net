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

  def handler do
    receive do
      {:init} ->
        IO.puts("#{inspect(self())}: received init")
        wait_for_nodes()
        spawn(fn -> ping_scheduler() end)
        handler()

      {:ping, src_node} ->
        IO.puts("#{inspect(self())}: received ping from #{inspect(src_node)}, sending ack")
        send({:handler, src_node}, {:ack, Node.self()})
        handler()

      {:ack, src_node} ->
        IO.puts("#{inspect(self())}: received ack from #{inspect(src_node)}")
        handler()
    end
  end

  def ping_scheduler() do
    Enum.each(Enum.shuffle(Node.list()), fn p ->
      :timer.sleep(5_000)
      IO.puts("#{inspect(self())}: sending ping to #{inspect(p)}")
      send({:handler, p}, {:ping, Node.self()})
    end)

    ping_scheduler()
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
