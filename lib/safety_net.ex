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

  # State should end up looking like:
  # state = %{
  #   id: id,
  #   coords: coords,
  #   incarnation: num,
  #   peers: %{
  #     :node_id =>
  #       %{
  #         coords: last_known_coords,
  #         status: last_known_status,
  #         incarnation: last_known_incarnation
  #       },
  #     ...
  #   }
  # }
  @impl true
  def init({id, peers, coords}) do
    peer_map =
      peers
      |> Enum.map(fn peer_id ->
        {peer_id, %{status: :alive, coords: nil}}
      end)
      |> Enum.into(%{})

    state = %__MODULE__{
      id: id,
      peers: peer_map,
      coords: coords
    }

    LighthouseServer.add_ship(own_membership(state))
    schedule_probe()
    time_to_move()

    {:ok, state}
  end

  @impl true
  def handle_cast({:ping, from_id, from_pid, _gossip}, state) do
    IO.puts("#{state.id}: received ping from #{from_id}, sending ack")
    send(from_pid, {:ack, state.id})
    {:noreply, state}
  end

  @impl true
  def handle_info(:probe, state) do
    # Pick a random peer and ping them
    # TODO: only pick alive nodes to ping
    if state.peers do
      {peer_id, _peer_data} = Enum.random(state.peers)
      gossip = prepare_gossip(state)
      GenServer.cast(via(peer_id), {:ping, state.id, self(), gossip})
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

  defp schedule_probe do
    Process.send_after(self(), :probe, 5000)
  end

  defp time_to_move do
    Process.send_after(self(), :chopchop, 5_000)
  end

  defp prepare_gossip(state) do
    # TODO: pick some peer's updates to share as well as own status
    [own_membership(state)]
  end

  defp own_membership(state) do
    %{
      id: state.id,
      coords: state.coords,
      status: :alive
    }
  end
end
