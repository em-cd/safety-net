defmodule SafetyNet do
  @moduledoc """
  Documentation for `SafetyNet`.
  """
  use GenServer
  defstruct [:id, :peers, :coords, :status]

  def start_link(id, peers \\ [], coords \\ {0, 0}, status \\ :alive) do
    GenServer.start_link(__MODULE__, {id, peers, coords, status}, name: via(id))
  end

  # State should end up looking like:
  # state = %{
  #   id: id,
  #   coords: coords,
  #   incarnation: num,
  #   status: status # (for search functionality only)
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
  def init({id, peers, coords, status}) do
    peer_map =
      peers
      |> Enum.map(fn peer_id ->
        {peer_id, %{status: :alive, coords: nil}}
      end)
      |> Enum.into(%{})

    state = %__MODULE__{
      id: id,
      coords: coords,
      status: status,
      peers: peer_map
    }

    LighthouseServer.add_ship(state)
    schedule_probe()
    # time_to_move()

    {:ok, state}
  end

  @doc """
  Once a ship is defined as MISSING, one ship calls this function to start looking for the closest ship.
  This functions creates a cascade where ships compare their distances between peers and find the closest one.
  It changes the participating ships statuses in:
  :visited -> to mark the ones already compared
  :closest -> temporary identifying the closest one
  :search -> appears after a timer runs down and it identifies the final closest ship
  :alive -> In case the missing ship is actually alive, it will set its status back to alive. No other action has been set.
  """
  def check_distance?(my_state, missing_ship) do
    IO.puts("I, #{my_state.id}, think #{missing_ship.id} is missing")

    # calculate my distace from missing ship
    my_distance = calculate_distance(my_state.coords, missing_ship.coords)
    IO.puts("I'm #{my_distance} clicks far away")
    # set status: :closest
    GenServer.cast(via(my_state.id), {:update_state, :closest})

    ask_peers(my_state, missing_ship, my_distance)
   end


  # ---------------------------------------- HANDLE INFOS
  @doc """
  :probe -> Pick a random peer and ping them
  :ack -> Prints receiving an ACK
  :search -> after wait() if the ship is still the closest to the missing one, sets its status to :search
  :chopchop -> makes the ships move . It's called by time_to_move()

  """
  # Ping a random peer
  @impl true
  def handle_info(:probe, state) do
    IO.puts(inspect(state.peers))
    # Pick a random peer and ping them
    # TODO: only pick alive nodes to ping
    if state.peers do
      {peer_id, _peer_data} = Enum.random(state.peers)
      gossip = prepare_gossip(state)
      GenServer.cast(via(peer_id), {:ping, state.id, self(), gossip})
    end

    schedule_probe()
    {:noreply, state}
  end

  # Print receiving an ACK
  @impl true
  def handle_info({:ack, from, gossip}, state) do
    #IO.puts("#{state.id}: received ack from #{from}")
    # Merge data
    new_state = merge_gossip(state, gossip)
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:search, state) do
    if state.status == :closest do
      GenServer.cast(via(state.id), {:update_state, :search})
      {:noreply, state}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(:chopchop, state) do
    %SafetyNet{coords: {old_x, old_y}} = state

    new_x = old_x + Enum.random([0 , 1])
    new_y = old_y + Enum.random([-1 ,0 , 1])
    new_state = %{state | coords: {new_x, new_y}}

    send_update_to_lighthouse(new_state)
    time_to_move()
    {:noreply, new_state}
  end

#-------------------------------------------- HANDLE CASTS
@doc """
:ping -> Receive a PING, send ACK back
:closer? -> called by check_distance/2
:update_state -> to change status in a state. Please pass a new status to the function.
NOTE: If the new status is :closest, it starts a timer to confirm it and turn it into :search
"""

  @impl true
  def handle_cast({:ping, from_id, from_pid, gossip}, state) do
    IO.puts("#{state.id}: received ping from #{from_id}, sending ack")

    # Merge data
    new_state = merge_gossip(state, gossip)

    send(from_pid, {:ack, state.id, prepare_gossip(new_state)})
    {:noreply, new_state}
  end


  @impl true
  def handle_cast({:closer?,{ missing, d, closest_ship}}, my_state) do
    cond do
      my_state.id == missing.id ->
      IO.puts("Hey, i'm alive!")
      GenServer.cast(via(my_state.id), {:update_state, :alive})
      {:noreply, my_state}


    my_state.status == :visited ->
      IO.puts("You've already asked me")
      {:noreply, my_state}

    true ->
          # set stat to visited
      GenServer.cast(via(my_state.id), {:update_state, :visited})

      # calculate distance
      distance = calculate_distance(my_state.coords, missing.coords)
      IO.puts("#{my_state.id}: I'm at #{distance} clicks")

      # compare distance
      if distance <= d do
        IO.puts("#{my_state.id}: I'm closer")
        GenServer.cast(via(my_state.id), {:update_state, :closest})
        GenServer.cast(via(closest_ship.id), {:update_state, :visited})

        ask_peers(my_state, missing, distance)

      else
        IO.puts("#{my_state.id}: I'm too far. I'll ask around")

        ask_peers(my_state, missing, d)
        end
      {:noreply, my_state}
    end
  end


  @impl true
  def handle_cast({:update_state, new}, state) do
    new_state = %{state | status: new}
    IO.puts("#{new_state.id} ----> STATUS: #{new_state.status}")
    send_update_to_lighthouse(new_state)
    if new == :closest do
      wait()
    end
    {:noreply, new_state}
  end


  # ------------------------------------------- HELPERS

  defp send_update_to_lighthouse(state) do
    LighthouseServer.update_ship(own_membership(state))
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

  defp merge_gossip(state, gossip) do
    new_peers = Enum.reduce(gossip, state.peers, fn %{id: id, coords: coords, status: status}, acc ->
      Map.update(acc, id, %{coords: coords, status: status}, fn _ ->
        %{coords: coords, status: status}
      end)
    end)

    %{state | peers: new_peers}
  end

  defp schedule_probe do
    Process.send_after(self(), :probe, 5000)
  end

  defp time_to_move do
    Process.send_after(self(), :chopchop, 5_000)
  end

  defp via(id), do: {:via, Registry, {SafetyNet, id}}

  defp wait do
    Process.send_after(self(), :search, 5_000)
  end

  defp calculate_distance({ship_x, ship_y}, {target_x, target_y}) do
   :math.sqrt((ship_x - target_x)**2 + (ship_y - target_y)**2)
  end

  defp ask_peers(my_state, missing_ship, my_distance) do
    Enum.each(my_state.peers, fn ship_id ->

    GenServer.cast(via(ship_id), {:closer?, {missing_ship, my_distance, my_state}}) end)
  end
end
