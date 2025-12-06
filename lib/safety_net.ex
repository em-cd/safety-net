defmodule SafetyNet do
  @moduledoc """
  Documentation for `SafetyNet`.
  """
  use GenServer

  defstruct [:id, :peers, :coords, :incarnation, :status, :pending]

  def start_link(id, peers \\ [], coords \\ {0, 0}, status \\ :alive) do
    GenServer.start_link(__MODULE__, {id, peers, coords, status}, name: {:global, id})
  end

  # State should end up looking like:
  # state = %{
  #   id: id,
  #   coords: coords,
  #   incarnation: num,
  #   status: status # (for search functionality only)
  #   peers: %{
  #     :node_id => %{
  #         coords: last_known_coords,
  #         status: last_known_status,
  #         incarnation: last_known_incarnation
  #       },
  #     ...
  #   },
  #   pending: %{
  #     node_id: {time_ping_sent, ping_origin}
  #   }
  # }
  @impl true
  def init({id, peers, coords, status}) do
    peer_map =
      peers
      |> Enum.map(fn peer_id ->
        {peer_id, %{status: :alive, coords: nil, incarnation: 0, suspect_since: nil}}
      end)
      |> Enum.into(%{})

    state = %__MODULE__{
      id: id,
      coords: coords,
      incarnation: 0,
      status: status,
      peers: peer_map,
      pending: %{}
    }

    LighthouseServer.add_ship(state)
    schedule(:probe, 0) # Start probing immediately
    schedule(:sweep, time_between_sweeps_ms())
    # schedule(:chopchop, time_between_moves)
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
    GenServer.cast({:global, my_state.id}, {:update_state, :closest})

    ask_peers(my_state, missing_ship, my_distance)
   end


  # ---------------------------------------- HANDLE INFOS
  @doc """
  :probe -> Pick a random peer and ping them
  :ack -> Prints receiving an ACK
  :search -> after wait() if the ship is still the closest to the missing one, sets its status to :search
  :chopchop -> makes the ships move . It's called by time_to_move()
  """

  # Periodic probe: pick a random peer and ping them
  @impl true
  def handle_info(:probe, state) do
    # IO.puts("#{state.id}: my peers are #{inspect(state.peers, pretty: true)}")

    pending =
      case state.peers do
        [] ->
          state.pending
        peers ->
          {peer_id, _peer_data} =
            peers
              |> Enum.filter(fn {_, peer} ->
                peer.status != :failed
              end)
              |> Enum.random()
          SafetyNet.Ping.send_ping(peer_id, state.id, state)
      end

    # Send a periodic update to the lighthouse
    send_update_to_lighthouse(state)

    schedule(:probe, protocol_period_ms())
    {:noreply, %{state | pending: pending}}
  end

  @impl true
  def handle_info(:search, state) do
    if state.status == :closest do
      GenServer.cast({:global, state.id}, {:update_state, :search})
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
    schedule(:chopchop, time_between_moves_ms())
    {:noreply, new_state}
  end

  # Periodically do a sweep for pending acks that have not been received.
  # Check also who needs to be flagged as suspected or failed.
  # This could mean a ship is in danger!
  @impl true
  def handle_info(:sweep, state) do
    state = state
    |> SafetyNet.FailureDetection.handle_overdue()
    |> SafetyNet.FailureDetection.handle_suspect()
    |> SafetyNet.FailureDetection.handle_failed()

    schedule(:sweep, time_between_sweeps_ms())
    {:noreply, state}
  end

#-------------------------------------------- HANDLE CASTS
@doc """
:ping -> Receive a PING, send ACK back
:ping_request -> Forward a PING to another node
:ack -> Receive an ACK, remove from pending and forward to another node if necessary
:closer? -> called by check_distance/2
:update_state -> to change status in a state. Please pass a new status to the function.
NOTE: If the new status is :closest, it starts a timer to confirm it and turn it into :search
"""

  # Handle ping: send ack back
  @impl true
  def handle_cast({:ping, from_id, gossip}, state) do
    # IO.puts("#{state.id}: received ping from #{from_id}, sending ack")
    state = SafetyNet.Gossip.merge(state, gossip)

    # Just for testing... simulate dodgy networks by not replying 100% of the time
    num = Enum.random(0..10)
    if num != 0, do: SafetyNet.Ping.send_ack(from_id, state.id, state)

    {:noreply, state}
  end

  # Handle ping request: send a ping to a node on behalf of another
  @impl true
  def handle_cast({:ping_request, from_id, suspect_id, gossip}, state) do
    # IO.puts("#{state.id}: received ping request from #{from_id}, Sending ping to #{suspect_id}")
    state = SafetyNet.Gossip.merge(state, gossip)
    pending = SafetyNet.Ping.send_ping(suspect_id, from_id, state)
    {:noreply, %{state | pending: pending}}
  end

  # Handle ack: remove node from pending list and forward to requesting node if necessary
  @impl true
  def handle_cast({:ack, from_id, gossip}, state) do
    state = SafetyNet.Gossip.merge(state, gossip)
    # IO.puts("#{state.id}: received ack from #{from_id}. Pending: #{inspect(state.pending)}")

    case Map.pop(state.pending, from_id) do
      {nil, _} ->
        # No such pending message, ignore
        {:noreply, state}
      {%{origin: origin_id}, pending} when origin_id == state.id ->
        # We requested this ack, nothing more to do
        {:noreply, %{state | pending: pending}}
      {%{origin: origin_id}, pending} ->
        # Forward the ack to the requesting node
        SafetyNet.Ping.send_ack(origin_id, from_id, state)
        {:noreply, %{state | pending: pending}}
    end
  end

  @impl true
  def handle_cast({:closer?,{ missing, d, closest_ship}}, my_state) do
    cond do
      my_state.id == missing.id ->
      IO.puts("Hey, i'm alive!")
      GenServer.cast({:global, my_state.id}, {:update_state, :alive})
      {:noreply, my_state}

    my_state.status == :visited ->
      IO.puts("You've already asked me")
      {:noreply, my_state}

    true ->
          # set stat to visited
      GenServer.cast({:global, my_state.id}, {:update_state, :visited})

      # calculate distance
      distance = calculate_distance(my_state.coords, missing.coords)
      IO.puts("#{my_state.id}: I'm at #{distance} clicks")

      # compare distance
      if distance <= d do
        IO.puts("#{my_state.id}: I'm closer")
        GenServer.cast({:global, my_state.id}, {:update_state, :closest})
        GenServer.cast({:global, closest_ship.id}, {:update_state, :visited})

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
      schedule(:search, 5000)
    end
    {:noreply, new_state}
  end


  # ------------------------------------------- HELPERS

  defp calculate_distance({ship_x, ship_y}, {target_x, target_y}) do
   :math.sqrt((ship_x - target_x)**2 + (ship_y - target_y)**2)
  end

  defp ask_peers(my_state, missing_ship, my_distance) do
    Enum.each(my_state.peers, fn ship_id ->

    GenServer.cast({:global, ship_id}, {:closer?, {missing_ship, my_distance, my_state}}) end)
  end

  # Send my update to the Lighthouse, formatted nicely
  defp send_update_to_lighthouse(state) do
    LighthouseServer.update_ship(%{
      id: state.id,
      coords: state.coords,
      status: state.status,
      incarnation: state.incarnation
    })
  end

  # Schedule a job, e.g. a probe or updating the coordinates
  defp schedule(message, timer), do: Process.send_after(self(), message, timer)

  # Full SWIM protocol period
  defp protocol_period_ms, do: 5000
  # How often we check pending acks and suspected nodes
  defp time_between_sweeps_ms, do: 300
  # How often a ship's coordinates change
  defp time_between_moves_ms, do: 5000
end
