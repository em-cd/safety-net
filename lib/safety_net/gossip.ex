defmodule SafetyNet.Gossip do
  @moduledoc """
  Gossip module
  """

  @doc """
  Prepares gossip to send with a ping, ping-request or ack message
  """
  def prepare_gossip(state) do
    peers =
      state.peers
      |> Enum.shuffle()
      |> Enum.take(1) # Change number here to choose how many peers to gossip about

    [own_membership(state) | Enum.map(peers, &peer_membership/1)]
  end

  @doc """
  Merges gossip with current state
  """
  def merge(state, gossip) do
    Enum.reduce(gossip, state, fn node, acc_state ->
      %{id: id, coords: coords, status: status, incarnation: inc} = node

      cond do
        # This is a rumour about me!
        id == acc_state.id ->
          if status != :alive && inc == acc_state.incarnation do
            # Uh oh, someone suspects me. Update my incarnation number so they know I'm alive
            # IO.puts("#{acc_state.id}: Received a rumor about myself, bumping incarnation.")
            %{acc_state | incarnation: acc_state.incarnation + 1}
          else
            # The rumour says I'm alive or the incarnation number is old, either way I can ignore it
            acc_state
          end

        # This is a rumour about someone else
        true ->
          case acc_state.peers[id] do
            nil ->
              # It's a new node I didn't know about
              put_in(acc_state.peers[id], %{
                coords: coords,
                status: status,
                incarnation: inc,
                suspect_since: if(status == :suspect, do: System.monotonic_time(:millisecond), else: nil),
                search_started: false
              })
            %{incarnation: local_inc, status: local_status} = local_peer ->
              cond do
                # Never downgrade :failed to :suspect or :alive unless incarnation increases
                inc <= local_inc and local_status == :failed and status != :failed ->
                  acc_state
                # Higher incarnation number: this is news to me, I'll update my membership list
                inc > local_inc ->
                  put_in(acc_state.peers[id], %{
                    coords: coords,
                    status: status,
                    incarnation: inc,
                    suspect_since:
                      if status == :alive do
                        nil
                      else
                        local_peer.suspect_since || System.monotonic_time(:millisecond)
                      end,
                    search_started: false
                  })
                # Override local :alive status if the gossip says :suspect or :failed
                inc == local_inc and status != :alive and local_status == :alive ->
                  put_in(acc_state.peers[id], %{
                    coords: coords || local_peer.coords, # keep local coords if incoming coords are nil
                    status: status,
                    incarnation: inc,
                    suspect_since: local_peer.suspect_since || System.monotonic_time(:millisecond),
                    search_started: false
                  })
                # Same incarnation, node is alive: update metadata
                inc == local_inc and status == :alive and local_status == :alive ->
                  put_in(acc_state.peers[id], %{
                    local_peer | coords: coords || local_peer.coords # keep local coords if incoming coords are nil
                  })
                # Stale gossip, ignore
                true ->
                  acc_state
              end
          end
      end
    end)
  end

  @doc"""
  Gossip about a specific node
  Also send own gossip because why not
  """
  def gossip_about(peer_id, state) do
    peer = {peer_id, state.peers[peer_id]}
    [own_membership(state), peer_membership(peer)]
  end

  # Format my state to send as gossip
  defp own_membership(state) do
    search_status =
      case state.search_status do
        nil -> :alive
        search -> {:searching_for, search}
      end

    %{
      id: state.id,
      coords: state.coords,
      status: search_status,
      incarnation: state.incarnation
    }
  end

  # Format my peer's state to send as gossip
  defp peer_membership({id, %{coords: coords, status: status, incarnation: incarnation}}) do
    %{
      id: id,
      coords: coords,
      status: status,
      incarnation: incarnation
    }
  end

end
