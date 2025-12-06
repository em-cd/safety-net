defmodule SafetyNet.FailureDetectionTest do
  use ExUnit.Case
  doctest SafetyNet

  describe "detect_failed/1" do
    test "returns failed ids" do
      now = System.monotonic_time(:millisecond)

      state = %{
        peers: %{
          suspect_only: %{coords: {0,0}, status: :suspect, incarnation: 1, suspect_since: now},
          another_suspect_only: %{coords: {0,0}, status: :suspect, incarnation: 1, suspect_since: nil},
          really_failed: %{coords: {0,0}, status: :suspect, incarnation: 1, suspect_since: now - 100000}
        }
      }

      failed_ids = SafetyNet.FailureDetection.detect_failed(state)
      assert failed_ids == [:really_failed]
    end
  end

  describe "handle_suspect/1" do
    test "sets overdue as suspect" do
      state = %{
        id: :A,
        peers: %{
          suspect: %{coords: {0,0}, status: :alive, incarnation: 1, suspect_since: nil},
        },
        pending: %{
          suspect: %{
            origin: :A,
            sent_at: System.monotonic_time(:millisecond) - 10000,
            ping_requests_sent: true
          }
        }
      }

      new_state = SafetyNet.FailureDetection.handle_suspect(state)
      assert new_state.peers[:suspect].status == :suspect
      assert new_state.peers[:suspect].suspect_since != nil
      assert new_state.pending[:suspect] != nil # should not remove from pending
    end
  end
end
