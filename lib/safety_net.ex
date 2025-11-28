defmodule SafetyNet do
  @moduledoc """
  Documentation for `SafetyNet`.
  """
  use GenServer

  defstruct [:id, :peers, :coords, :status]

  def start_link(id, peers \\ [], coords \\ {0, 0}, status \\ :alive) do
    GenServer.start_link(__MODULE__, {id, peers, coords, status}, name: via(id))
  end

  defp via(id), do: {:via, Registry, {SafetyNet, id}}

  @impl true
  def init({id, peers, coords, status}) do
    state = %__MODULE__{
      id: id,
      peers: peers,
      coords: coords,
      status: status
    }

    LighthouseServer.add_ship(state)
    schedule_probe()
    time_to_move()

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

  # ------------------------------- MOVEMENT
  @impl true
  def handle_info(:chopchop, state) do
    %SafetyNet{coords: {old_x, old_y}} = state

    new_x = old_x + Enum.random([0 , 1])
    new_y = old_y + Enum.random([-1 ,0 , 1])
    new_state = %{state | coords: {new_x, new_y}}

    LighthouseServer.update_ship(new_state)
    time_to_move()
    {:noreply, new_state}
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

  defp time_to_move do
    Process.send_after(self(), :chopchop, 5_000)
  end
end
