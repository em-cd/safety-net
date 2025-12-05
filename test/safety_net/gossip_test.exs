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

  describe "merge/2" do
    test "bumps own incarnation when gossip claims I am suspect" do
      state = state()
      gossip = [
        %{id: :A, coords: {0,0}, status: :suspect, incarnation: 1}
      ]

      merged = SafetyNet.Gossip.merge(state, gossip)
      assert merged.incarnation == state.incarnation + 1
      assert merged.peers == %{}
    end

    test "ignore gossip that claims I am suspect if the incarnation number is old" do
      state = state()
      gossip = [
        %{id: :A, coords: {0,0}, status: :suspect, incarnation: 0}
      ]

      merged = SafetyNet.Gossip.merge(state, gossip)
      assert merged == state
    end

    test "updates a peer when gossip has higher incarnation" do
      state =
        state(%{
          :B => %{coords: {1,1}, status: :alive, incarnation: 1}
        })
      gossip = [
        %{id: :B, coords: {9,9}, status: :suspect, incarnation: 2}
      ]

      merged = SafetyNet.Gossip.merge(state, gossip)

      assert merged.peers[:B] == %{
        coords: {9,9},
        status: :suspect,
        incarnation: 2
      }
    end

    test "ignores stale gossip with lower incarnation" do
      state =
        state(%{
          :B => %{coords: {1,1}, status: :alive, incarnation: 3}
        })
      gossip = [
        %{id: :B, coords: {9,9}, status: :suspect, incarnation: 2}
      ]

      merged = SafetyNet.Gossip.merge(state, gossip)

      assert merged.peers[:B] == %{
        coords: {1,1},
        status: :alive,
        incarnation: 3
      }
    end

    test "adds a peer if not present" do
      state = state()
      gossip = [
        %{id: :B, coords: {5,5}, status: :alive, incarnation: 1}
      ]

      merged = SafetyNet.Gossip.merge(state, gossip)

      assert merged.peers[:B] == %{
        coords: {5,5},
        status: :alive,
        incarnation: 1
      }
    end
  end
end
