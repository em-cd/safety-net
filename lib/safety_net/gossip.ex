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
          if status == :suspect && inc == state.incarnation do
            # Uh oh, someone suspects me. Update my incarnation number so they know I'm alive
            new_state =
              acc_state
              |> Map.update!(:incarnation, &(&1 + 1))
            # IO.puts("#{acc_state.id}: Received a rumor about myself, bumping incarnation.")
            new_state
          else
            # The rumour says I'm alive or the incarnation number is old, either way I can ignore it
            acc_state
          end

        # This is a rumour about someone else
        true ->
          case state.peers[id] do
            nil ->
              # It's a new node I didn't know about
              put_in(acc_state.peers[id], %{
                coords: coords,
                status: status,
                incarnation: inc
              })
            %{incarnation: local_inc} = _local_peer ->
              if inc > local_inc do
                # This is news to me, I'll update my membership list
                put_in(acc_state.peers[id], %{
                  coords: coords,
                  status: status,
                  incarnation: inc
                })
              else
                # Stale gossip, ignore
                acc_state
              end
          end
      end
    end)
  end

  # Format my state to send as gossip
  defp own_membership(state) do
    %{
      id: state.id,
      coords: state.coords,
      status: state.status,
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
