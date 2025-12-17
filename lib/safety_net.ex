defmodule SafetyNet do
  @moduledoc """
  Documentation for `SafetyNet`.
  """
  use GenServer

  defstruct [:id, :peers, :coords, :incarnation, :search_status, :pending]

  def start_link(id, peers \\ [], coords \\ {0, 0}) do
    GenServer.start_link(__MODULE__, {id, peers, coords}, name: {:global, id})
  end

  # state = %{
  #   id: id,
  #   coords: coords,
  #   incarnation: num,
  #   search_status: nil or node_id,
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
  def init({id, peers, coords}) do
    peer_map =
      peers
      |> Enum.map(fn peer_id ->
        {peer_id, %{
          status: :alive,
          coords: nil,
          incarnation: 0,
          suspect_since: nil,
          search_started: false
          }}
      end)
      |> Enum.into(%{})

    state = %__MODULE__{
      id: id,
      coords: coords,
      incarnation: 0,
      search_status: nil,
      peers: peer_map,
      pending: %{}
    }

    SafetyNet.PubSub.broadcast(:ship_update, {id, coords, :alive, 0})

    schedule(:probe, 0) # Start probing immediately
    schedule(:sweep, time_between_sweeps_ms())
    schedule(:move, time_between_moves_ms())

    {:ok, state}
  end


  # ---------------------------------------- HANDLE INFOS

  # Periodic probe: pick a random peer and ping them
  @impl true
  def handle_info(:probe, state) do
    IO.puts("#{state.id}: status: #{inspect(get_status(state))}, coords: #{inspect(state.coords)}, incarnation: #{state.incarnation}. My peers are: #{inspect(state.peers, pretty: true)}")

    pending =
      case state.peers do
        [] ->
          state.pending
        peers ->
          live_peers = Enum.filter(peers, fn {_, peer} -> peer.status != :failed end)

          case live_peers do
            [] ->
              IO.puts("#{state.id}: no live peers to ping :(")
              state.pending

            _ ->
              {peer_id, _peer_data} = Enum.random(live_peers)
              SafetyNet.Ping.send_ping(peer_id, state.id, state)
          end
      end

    # Send an update to the lighthouse
    send_update_to_lighthouse(state)

    schedule(:probe, protocol_period_ms())
    {:noreply, %{state | pending: pending}}
  end

  # Periodically update the ship's coordinates
  @impl true
  def handle_info(:move, state) do
    cond do
      # If we're searching, stop moving randomly
      state.search_status != nil ->
        schedule(:move, time_between_moves_ms())
        {:noreply, state}
      # Otherwise, keep sailing ⛵
      true ->
        new_state = %{state | coords: SafetyNet.ShipMovement.move(state.coords)}
        send_update_to_lighthouse(new_state)
        schedule(:move, time_between_moves_ms())
        {:noreply, new_state}
    end
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

    # Check if there are failed nodes that I didn't search for already
    failed_peers =
      state.peers
      |> Enum.filter(fn {_id, peer} ->
        peer.status == :failed and peer.search_started == false
      end)

    # Start a search if I didn't already
    state =
      Enum.reduce(failed_peers, state, fn {id, peer}, acc ->
        if peer.coords do
          SafetyNet.Search.search(acc, id)
        else
          acc
        end
      end)

    # If I am searching for a node, and they turned out to be alive, reset my search_status
    state =
      case state.search_status do
        nil ->
          state
        node ->
          peer = state.peers[node]
          if peer && peer.status != :failed do
            %{state | search_status: nil}
          else
            state
          end
      end

    # Update Lighthouse in case of changes
    send_update_to_lighthouse(state)

    schedule(:sweep, time_between_sweeps_ms())
    {:noreply, state}
  end

#-------------------------------------------- HANDLE CASTS

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

  # Handle closer?: refute the rumour if it's false, otherwise continue the search for the missing ship
  @impl true
  def handle_cast({:closer?, from_id, missing_id, gossip}, my_state) do
    my_state = SafetyNet.Gossip.merge(my_state, gossip)

    cond do
      # The ship didn't really fail, let's update the ship who sent me this message with a ping
      my_state.peers[missing_id].status != :failed ->
        gossip = SafetyNet.Gossip.gossip_about(missing_id, my_state)
        pending = SafetyNet.Ping.send_ping(from_id, my_state.id, my_state, gossip)
        {:noreply, %{my_state | pending: pending}}

      # I'm not already searching, continue with the search
      my_state.search_status == nil ->
        my_state = SafetyNet.Search.search(my_state, missing_id)
        {:noreply, my_state}

      # I'm already searching for someone, do nothing
      true ->
        {:noreply, my_state}
    end
  end

  # ------------------------------------------- HELPERS

  # Send my update to the Lighthouse
  defp send_update_to_lighthouse(state) do
    status = get_status(state)
    SafetyNet.PubSub.broadcast(:ship_update, {state.id, state.coords, status, state.incarnation})
  end

  # Return my status: alive or searching for missing ship
  defp get_status(state) do
    case state.search_status do
      nil -> :alive
      search -> {:searching_for, search}
    end
  end

  # Schedule a job, e.g. a probe or updating the coordinates
  defp schedule(message, timer), do: Process.send_after(self(), message, timer)

  # Full SWIM protocol period
  defp protocol_period_ms, do: 5000
  # How often we check pending acks and suspected nodes
  defp time_between_sweeps_ms, do: 300
  # How often a ship's coordinates change
  defp time_between_moves_ms, do: 2000
end
