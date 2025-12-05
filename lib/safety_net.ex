defmodule SafetyNet do
  @moduledoc """
  Documentation for `SafetyNet`.
  """
  use GenServer

  defstruct [:id, :peers, :coords, :status, :pending]

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
        {peer_id, %{status: :alive, coords: nil}}
      end)
      |> Enum.into(%{})

    state = %__MODULE__{
      id: id,
      coords: coords,
      status: status,
      peers: peer_map,
      pending: %{}
    }

    LighthouseServer.add_ship(state)
    schedule(:probe, 0) # Start probing immediately
    schedule(:sweep, time_between_sweeps())
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
  # Pick a random peer and ping them
  @impl true
  def handle_info(:probe, state) do
    pending =
      case state.peers do
        [] ->
          state.pending
        peers ->
          # TODO: only pick alive nodes to ping
          {peer_id, _peer_data} = Enum.random(peers)
          send_ping(peer_id, state.id, state)
      end

    schedule(:probe, protocol_period())
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
    schedule(:chopchop, time_between_moves())
    {:noreply, new_state}
  end

  # Periodically do a sweep for pending acks that have not been received.
  # This could mean a ship is in danger!
  @impl true
  def handle_info(:sweep, state) do
    now = System.monotonic_time(:millisecond)

    overdue =
      state.pending
      |> Enum.filter(fn {_peer, {sent_at, origin_id}} ->
        # For now we only check for pings that we originally requested.
        origin_id == state.id && sent_at + timeout() <= now
      end)
      |> Enum.map(&elem(&1, 0))

    if overdue != [], do: IO.puts("#{state.id}: Acks overdue! Suspicious ships: #{inspect(overdue)}")

    Enum.each(overdue, fn overdue_id ->
      # Pick k random peers
      targets = state.peers
        |> Enum.reject(fn {id, _} -> id == overdue_id end)
        |> Enum.map(fn {id, _} -> id end)
        |> Enum.shuffle()
        |> Enum.take(1) # Change number here to however many nodes we want to request pings from

      # Send each peer a ping request
      Enum.each(targets, fn peer_id ->
        GenServer.cast({:global, peer_id}, {:ping_request, state.id, overdue_id, prepare_gossip(state)})
      end)
    end)

    # Mark all overdue nodes as suspect
    updated_peers =
      Enum.reduce(overdue, state.peers, fn overdue_id, acc_peers ->
        Map.update!(acc_peers, overdue_id, fn peer ->
          Map.put(peer, :status, :suspect)
        end)
      end)

    # Remove them from pending
    pending = Map.drop(state.pending, overdue)

    schedule(:sweep, time_between_sweeps())
    {:noreply, %{state | peers: updated_peers, pending: pending}}
  end

#-------------------------------------------- HANDLE CASTS
@doc """
:ping -> Receive a PING, send ACK back
:closer? -> called by check_distance/2
:update_state -> to change status in a state. Please pass a new status to the function.
NOTE: If the new status is :closest, it starts a timer to confirm it and turn it into :search
"""

  # Handle ping: send ack back
  @impl true
  def handle_cast({:ping, from_id, gossip}, state) do
    # IO.puts("#{state.id}: received ping from #{from_id}, sending ack")
    state = merge_gossip(state, gossip)

    # Just for testing... flip a coin, if it's heads you reply, if it's tails you don't
    num = Enum.random(0..1)
    if num == 0, do: GenServer.cast({:global, from_id}, {:ack, state.id, prepare_gossip(state)})

    {:noreply, state}
  end

  # Handle ping request: send a ping to a node on behalf of another
  @impl true
  def handle_cast({:ping_request, from_id, to_id, gossip}, state) do
    IO.puts("#{state.id}: received ping request from #{from_id}, Sending ping to #{to_id}")
    state = merge_gossip(state, gossip)
    pending = send_ping(to_id, from_id, state)
    {:noreply, %{state | pending: pending}}
  end

  # Handle ack: remove node from pending list and forward to requesting node if necessary
  @impl true
  def handle_cast({:ack, from_id, gossip}, state) do
    state = merge_gossip(state, gossip)

    case Map.pop(state.pending, from_id) do
      {nil, _} ->
        # No such pending message, ignore
        {:noreply, state}
      {{_, origin_id}, pending} when origin_id == state.id ->
        # We requested this ack, nothing more to do
        IO.puts("#{state.id}: received ack from #{from_id}, ok. Pending: #{inspect(pending)}")
        {:noreply, %{state | pending: pending}}
      {{_, origin_id}, pending} ->
        # Forward the ack to the requesting node
        IO.puts("#{state.id}: received ack from #{from_id}, forwarding to #{origin_id}. Pending: #{inspect(pending)}")
        GenServer.cast({:global, origin_id}, {:ack, from_id, prepare_gossip(state)})
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

  # Sends a ping packet and files a pending ack
  # Returns the new map of pending acks
  defp send_ping(peer_id, origin_id, state) do
    gossip = prepare_gossip(state)
    GenServer.cast({:global, peer_id}, {:ping, state.id, gossip})
    now = System.monotonic_time(:millisecond)
    Map.put(state.pending, peer_id, {now, origin_id})
  end

  # Prepares gossip to send with a ping, ping-request or ack message
  defp prepare_gossip(state) do
    peers =
      state.peers
      |> Enum.shuffle()
      |> Enum.take(1) # Change number here to choose how many peers to gossip about

    [own_membership(state) | Enum.map(peers, &peer_membership/1)]
  end

  # Format my state to send as gossip
  defp own_membership(state) do
    %{
      id: state.id,
      coords: state.coords,
      status: state.status
    }
  end

  # Format my peer's state to send as gossip
  defp peer_membership({id, %{coords: coords, status: status}}) do
    %{
      id: id,
      coords: coords,
      status: status
    }
  end

  # Merge gossip with my state
  defp merge_gossip(state, gossip) do
    peers = Enum.reduce(gossip, state.peers, fn %{id: id, coords: coords, status: status}, acc ->
      Map.update(acc, id, %{coords: coords, status: status}, fn _ ->
        %{coords: coords, status: status}
      end)
    end)

    %{state | peers: peers}
  end

  defp calculate_distance({ship_x, ship_y}, {target_x, target_y}) do
   :math.sqrt((ship_x - target_x)**2 + (ship_y - target_y)**2)
  end

  defp ask_peers(my_state, missing_ship, my_distance) do
    Enum.each(my_state.peers, fn ship_id ->

    GenServer.cast({:global, ship_id}, {:closer?, {missing_ship, my_distance, my_state}}) end)
  end

  defp send_update_to_lighthouse(state) do
    LighthouseServer.update_ship(own_membership(state))
  end

  # Schedule a job, e.g. a probe or updating the coordinates
  defp schedule(message, timer), do: Process.send_after(self(), message, timer)

  # Full SWIM protocol period
  defp protocol_period, do: 5000
  # How often we check our missing acks to see if they need to be handled
  defp time_between_sweeps, do: 300
  # How much time before we send out ping requests for a missing ack
  defp timeout, do: 1000
  # How often a ship's coordinates change
  defp time_between_moves, do: 5000
end
