defmodule SafetyNet.GossipTest do
  use ExUnit.Case
  doctest SafetyNet

  # Helper to build a fake initial state
  defp state(peers \\ %{}) do
    %{
      id: :A,
      coords: {0, 0},
      status: :alive,
      incarnation: 1,
      peers: peers
    }
  end

  describe "when receiving gossip about a new peer" do
    test "adds a peer" do
      state = state()
      gossip = [
        %{id: :B, coords: {5,5}, status: :alive, incarnation: 1}
      ]

      merged = SafetyNet.Gossip.merge(state, gossip)

      assert merged.peers[:B] == %{
        coords: {5,5},
        status: :alive,
        incarnation: 1,
        suspect_since: nil,
        search_started: false
      }
    end
  end

  describe "when receiving gossip about myself" do
    test "bumps own incarnation when gossip claims I am suspect" do
      state = state()
      gossip = [
        %{id: :A, coords: {0,0}, status: :suspect, incarnation: 1}
      ]

      merged = SafetyNet.Gossip.merge(state, gossip)
      assert merged.incarnation == state.incarnation + 1
      assert merged.peers == %{}
    end

    test "bumps own incarnation when gossip claims I am failed" do
      state = state()
      gossip = [
        %{id: :A, coords: {0,0}, status: :failed, incarnation: 1}
      ]

      merged = SafetyNet.Gossip.merge(state, gossip)
      assert merged.incarnation == state.incarnation + 1
      assert merged.peers == %{}
    end

    test "ignore gossip that claims I am suspect if the incarnation number is old" do
      state = state()
      gossip = [
        %{id: :A, coords: {0,0}, status: :suspect, incarnation: state.incarnation - 1}
      ]

      merged = SafetyNet.Gossip.merge(state, gossip)
      assert merged == state
    end
  end

  describe "when receiving gossip about a peer being alive" do
    test "updates a peer when gossip has higher incarnation" do
      state =
        state(%{
          :B => %{coords: {1,1}, status: :alive, incarnation: 1, suspect_since: nil, search_started: false},
          :C => %{coords: {0,0}, status: :suspect, incarnation: 1, suspect_since: System.monotonic_time(:millisecond), search_started: false}
        })
      gossip = [
        %{id: :B, coords: {9,9}, status: :alive, incarnation: 2},
        %{id: :C, coords: {5,5}, status: :alive, incarnation: 2}
      ]
      merged = SafetyNet.Gossip.merge(state, gossip)

      assert merged.peers[:B] == %{
        coords: {9,9},
        status: :alive,
        incarnation: 2,
        suspect_since: nil,
        search_started: false
      }
      assert merged.peers[:C] == %{
        coords: {5,5},
        status: :alive,
        incarnation: 2,
        suspect_since: nil,
        search_started: false
      }
    end

    test "ignores stale gossip with lower or equal incarnation" do
      state =
        state(%{
          :B => %{coords: {1,1}, status: :alive, incarnation: 3, suspect_since: nil, search_started: false},
          :C => %{coords: {0,0}, status: :suspect, incarnation: 1, suspect_since: System.monotonic_time(:millisecond), search_started: false}
        })
      gossip = [
        %{id: :B, coords: {9,9}, status: :alive, incarnation: 2},
        %{id: :C, coords: {5,5}, status: :alive, incarnation: 1}
      ]
      merged = SafetyNet.Gossip.merge(state, gossip)

      assert merged.peers[:B] == state.peers[:B]
      assert merged.peers[:C] == state.peers[:C]
    end
  end

  describe "when receiving gossip about a peer being suspect" do
    test "updates a peer when gossip has higher incarnation" do
      suspect_since = System.monotonic_time(:millisecond)
      state =
        state(%{
          :B => %{coords: {1,1}, status: :alive, incarnation: 1, suspect_since: nil, search_started: false},
          :C => %{coords: {0,0}, status: :suspect, incarnation: 1, suspect_since: suspect_since, search_started: false}
        })
      gossip = [
        %{id: :B, coords: {9,9}, status: :suspect, incarnation: 2},
        %{id: :C, coords: {5,5}, status: :suspect, incarnation: 2}
      ]
      merged = SafetyNet.Gossip.merge(state, gossip)

      assert merged.peers[:B].coords == {9,9}
      assert merged.peers[:B].status == :suspect
      assert merged.peers[:B].incarnation == 2
      assert merged.peers[:B] != nil

      assert merged.peers[:C] == %{
        coords: {5,5},
        status: :suspect,
        incarnation: 2,
        suspect_since: suspect_since,
        search_started: false
      }
    end

    test "updates the peer if I think they are alive and the incarnation is the same" do
      state =
        state(%{
          :B => %{coords: {1,1}, status: :alive, incarnation: 1, suspect_since: nil, search_started: false},
        })
      gossip = [
        %{id: :B, coords: {9,9}, status: :suspect, incarnation: 1},
      ]
      merged = SafetyNet.Gossip.merge(state, gossip)

      assert merged.peers[:B].coords == {9,9}
      assert merged.peers[:B].status == :suspect
      assert merged.peers[:B].incarnation == 1
      assert merged.peers[:B] != nil
    end

    test "ignores stale gossip with lower incarnation if I think they are alive" do
      state =
        state(%{
          :B => %{coords: {1,1}, status: :alive, incarnation: 3, suspect_since: nil, search_started: false}
        })
      gossip = [
        %{id: :B, coords: {9,9}, status: :suspect, incarnation: 2},
      ]
      merged = SafetyNet.Gossip.merge(state, gossip)

      assert merged.peers[:B] == state.peers[:B]
    end

    test "ignores stale gossip with lower or equal incarnation if I already think they are suspect" do
      suspect_since = System.monotonic_time(:millisecond)
      state =
        state(%{
          :B => %{coords: {1,1}, status: :suspect, incarnation: 2, suspect_since: suspect_since, search_started: false}
        })
      gossip = [
        %{id: :B, coords: {9,9}, status: :suspect, incarnation: 2},
      ]
      merged = SafetyNet.Gossip.merge(state, gossip)

      assert merged.peers[:B] == state.peers[:B]
    end
  end

  describe "when receiving gossip about a failed peer" do
    test "updates a peer when gossip has higher incarnation" do
      suspect_since = System.monotonic_time(:millisecond)
      state =
        state(%{
          :B => %{coords: {1,1}, status: :alive, incarnation: 1, suspect_since: nil, search_started: false},
          :C => %{coords: {0,0}, status: :suspect, incarnation: 1, suspect_since: suspect_since, search_started: false}
        })
      gossip = [
        %{id: :B, coords: {9,9}, status: :failed, incarnation: 2},
        %{id: :C, coords: {5,5}, status: :failed, incarnation: 2}
      ]
      merged = SafetyNet.Gossip.merge(state, gossip)

      assert merged.peers[:B].coords == {9,9}
      assert merged.peers[:B].status == :failed
      assert merged.peers[:B].incarnation == 2
      assert merged.peers[:B] != nil

      assert merged.peers[:C] == %{
        coords: {5,5},
        status: :failed,
        incarnation: 2,
        suspect_since: suspect_since,
        search_started: false
      }
    end

    test "updates the peer if I think they are alive and the incarnation is the same" do
      state =
        state(%{
          :B => %{coords: {1,1}, status: :alive, incarnation: 1, suspect_since: nil, search_started: false},
        })
      gossip = [
        %{id: :B, coords: {9,9}, status: :failed, incarnation: 1},
      ]
      merged = SafetyNet.Gossip.merge(state, gossip)

      assert merged.peers[:B].coords == {9,9}
      assert merged.peers[:B].status == :failed
      assert merged.peers[:B].incarnation == 1
      assert merged.peers[:B] != nil
    end

    test "ignores stale gossip with lower incarnation if I think they are alive" do
      state =
        state(%{
          :B => %{coords: {1,1}, status: :alive, incarnation: 3, suspect_since: nil, search_started: false}
        })
      gossip = [
        %{id: :B, coords: {9,9}, status: :failed, incarnation: 2},
      ]
      merged = SafetyNet.Gossip.merge(state, gossip)

      assert merged.peers[:B] == state.peers[:B]
    end

    test "ignores stale gossip with lower or equal incarnation if I already think they are failed" do
      suspect_since = System.monotonic_time(:millisecond)
      state =
        state(%{
          :B => %{coords: {1,1}, status: :failed, incarnation: 2, suspect_since: suspect_since, search_started: false}
        })
      gossip = [
        %{id: :B, coords: {9,9}, status: :failed, incarnation: 2},
      ]
      merged = SafetyNet.Gossip.merge(state, gossip)

      assert merged.peers[:B] == state.peers[:B]
    end

  end
end
