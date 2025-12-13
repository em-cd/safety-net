defmodule SafetyNet.Ping do
  @moduledoc """
  Ping module
  Handles message sending: pings, ping-requests, acks
  """

  @doc """
  Sends a ping packet and files a pending ack
  Returns the new map of pending acks
  """
  def send_ping(peer_id, origin_id, state, gossip \\ nil) do
    # IO.puts("#{state.id}: pinging #{peer_id}")
    gossip = gossip || SafetyNet.Gossip.prepare_gossip(state)
    GenServer.cast({:global, peer_id}, {:ping, state.id, gossip})
    now = System.monotonic_time(:millisecond)
    Map.put(state.pending, peer_id, %{sent_at: now, origin: origin_id, ping_requests_sent: false})
  end

  @doc """
  Send a ping request packet to a peer, so that they will ping the suspected node on our behalf
  """
  def send_ping_request(peer_id, suspect_id, state) do
    # IO.puts("#{state.id}: sending #{peer_id} a ping request for #{suspect_id}")
    GenServer.cast({:global, peer_id}, {:ping_request, state.id, suspect_id, SafetyNet.Gossip.prepare_gossip(state)})
  end

  @doc """
  Send an ack, including who it's from so the recipient knows whether to forward it or not
  Include gossip about the node who pinged us so they can know what's being said about them
  """
  def send_ack(to_id, from_id, state) do
    # IO.puts("#{state.id}: sending an ack to #{to_id} from #{from_id}")
    gossip = SafetyNet.Gossip.gossip_about(to_id, state)
    GenServer.cast({:global, to_id}, {:ack, from_id, gossip})
  end

end
