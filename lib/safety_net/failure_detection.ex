defmodule SafetyNet.FailureDetection do
  @moduledoc """
  Failure Detection module
  """

  @doc """
  Handle overdue nodes: send ping requests, mark as suspect
  Returns the updated state
  """
  def handle_overdue(state) do
    overdue_ids = detect_overdue(state)
    if overdue_ids != [] do
      IO.puts("#{state.id}: Acks overdue! Requesting pings for #{inspect(overdue_ids)}")

      # Long version for debugging...
      # IO.puts("#{state.id}: Acks overdue!
      # Requesting pings for #{inspect(overdue_ids)}
      # suspect: #{inspect(detect_suspect(state))},
      # failed: #{inspect(detect_failed(state))}.
      # \n Peers: #{inspect(state.peers, pretty: true)}
      # \n Pending: #{inspect(state.pending, pretty: true)}")
    end

    Enum.each(overdue_ids, fn overdue_id ->
      # Pick k random peers
      targets =
        state.peers
        |> Enum.reject(fn {id, _} -> id == overdue_id end)
        |> Enum.map(fn {id, _} -> id end)
        |> Enum.shuffle()
        |> Enum.take(1) # Change number here to however many nodes we want to request pings from

      Enum.each(targets, fn peer_id ->
        SafetyNet.Ping.send_ping_request(peer_id, overdue_id, state)
      end)
    end)

    updated_pending =
      Enum.reduce(overdue_ids, state.pending, fn overdue_id, acc ->
        Map.update!(acc, overdue_id, fn p ->
          %{p | ping_requests_sent: true}
        end)
      end)

    %{state | pending: updated_pending}
  end

  @doc """
  Handle suspect nodes: mark as suspect
  Returns the updated state
  """
  def handle_suspect(state) do
    now = System.monotonic_time(:millisecond)

    suspect_ids = detect_suspect(state)
    if suspect_ids != [] do
      IO.puts("#{state.id}: Suspect ships: #{inspect(suspect_ids)}")

      # Long version for debugging...
      # IO.puts("#{state.id}: Acks overdue!
      # Suspect ships: #{inspect(suspect_ids)},
      # overdue: #{inspect(detect_overdue(state))},
      # failed: #{inspect(detect_failed(state))}.
      # \n Peers: #{inspect(state.peers, pretty: true)}
      # \n Pending: #{inspect(state.pending, pretty: true)}
      # \n #{now}
      # ")
    end

    updated_peers =
      Enum.reduce(suspect_ids, state.peers, fn id, peers ->
        # Mark node as suspect
        Map.update!(peers, id, fn p ->
          %{p | status: :suspect} |> Map.put(:suspect_since, now)
        end)
      end)

    %{state | peers: updated_peers}
  end

  @doc """
  Handle failed nodes: mark as failed, remove from pending
  Returns the updated state
  """
  def handle_failed(state) do
    failed_ids = detect_failed(state)

    if failed_ids != [] do
      IO.puts("#{state.id}: SOS, #{inspect(failed_ids)} failed!")
    end

    peers =
      Enum.reduce(failed_ids, state.peers, fn failed_id, acc ->
        LighthouseServer.update_ship(%{
          id: failed_id,
          coords: acc[failed_id].coords,
          status: :failed,
          incarnation: acc[failed_id].incarnation
        })
        # Return map
        Map.update!(acc, failed_id, fn p ->
          %{p | status: :failed}
        end)
      end)

    pending = Map.drop(state.pending, failed_ids)

    %{state | peers: peers, pending: pending}
  end

  @doc """
  Detects nodes with overdue acks that we are waiting for
  Returns a list of their ids
  """
  def detect_overdue(state) do
    now = System.monotonic_time(:millisecond)

    state.pending
      |> Enum.filter(fn {id, %{sent_at: sent_at, origin: origin_id, ping_requests_sent: ping_requests_sent}} ->
        # We only check for pings that we originally requested
        origin_id == state.id and
          sent_at + ping_timeout_ms() <= now and
          not ping_requests_sent and # and do not send multiple rounds of ping requests
          state.peers[id].status != :failed # ignore failed nodes
      end)
      |> Enum.map(&elem(&1, 0))
  end

  @doc """
  Detects nodes with overdue acks that should be marked as suspect
  Returns a list of their ids
  """
  def detect_suspect(state) do
    now = System.monotonic_time(:millisecond)

    state.pending
      |> Enum.filter(fn {id, %{sent_at: sent_at, origin: origin_id}} ->
        # We only check for pings that we originally requested
        origin_id == state.id and
          sent_at + suspect_timeout_ms() <= now and
          state.peers[id].status == :alive
      end)
      |> Enum.map(&elem(&1, 0))
  end

  @doc"""
  Detect failed nodes and returns a list of their ids
  """
  def detect_failed(state) do
    now = System.monotonic_time(:millisecond)

    state.peers
      |> Enum.filter(fn {_id, peer} ->
        peer.status == :suspect and
          peer.suspect_since != nil and
          peer.suspect_since + failed_timeout_ms() <= now
      end)
      |> Enum.map(&elem(&1, 0))
  end

  # How much time before we send out ping requests for a missing ack
  defp ping_timeout_ms, do: 800

  # How much time before we declare a ship as suspect
  defp suspect_timeout_ms, do: 4000

  # How much time before we declare a suspect ship as failed
  defp failed_timeout_ms, do: 8000
end
