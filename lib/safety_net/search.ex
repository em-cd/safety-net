defmodule SafetyNet.Search do
  @moduledoc """
  Search module
  Upon failure, we send out a search signal to the closest ship to the missing one.
  """

  @doc """
  Once a ship is defined as MISSING, one ship calls this function to start looking for the closest ship.
  This functions creates a cascade where ships compare their distances between peers and find the closest one.
  The closest ship sets their status to :searching.
  """
  def search(my_state, missing_ship_id) do
    missing_ship_coords = my_state.peers[missing_ship_id].coords

    # calculate my distace from missing ship
    my_distance = calculate_distance(my_state.coords, missing_ship_coords)
    IO.puts("#{my_state.id}: I'm #{my_distance} clicks far away from #{missing_ship_id}")

    {closest_id, closest_distance} = Enum.reduce(my_state.peers, {my_state.id, my_distance}, fn
      {id, %{coords: coords}}, {acc_id, acc_dist}
      when id != missing_ship_id and coords != nil ->
        dist = calculate_distance(coords, missing_ship_coords)

        if dist < acc_dist do
          {id, dist}
        else
          {acc_id, acc_dist}
        end

      # Skip the missing ship and peers without coords
      _, acc ->
        acc
    end)

    # Logging
    msg = if closest_id != my_state.id do
      "#{my_state.id}: closest peer to #{missing_ship_id} is #{closest_id}, distance: #{closest_distance}"
    else
      "#{my_state.id}: I am the closest ship I know about to #{missing_ship_id}"
    end
    IO.puts(msg)
    SafetyNet.PubSub.broadcast(:message, msg)

    # If someone else is closer, contact them
    if closest_id != my_state.id, do: ask_peer(closest_id, my_state, missing_ship_id)

    # Set search_started to true
    peers =
      Map.put(
        my_state.peers,
        missing_ship_id,
        %{ my_state.peers[missing_ship_id] | search_started: true }
      )

    # Set my status to searching if I am closest at this point
    my_search_status = if closest_id == my_state.id, do: missing_ship_id, else: my_state.search_status

    %{my_state | peers: peers, search_status: my_search_status}
  end

  # Sends a :closer? message to a peer
  defp ask_peer(ship_id, my_state, missing_ship_id) do
    GenServer.cast({:global, ship_id}, {:closer?, my_state.id, missing_ship_id, SafetyNet.Gossip.gossip_about(missing_ship_id, my_state)})
  end

  # Calculates the distance between two ships
  def calculate_distance({ship_x, ship_y}, {target_x, target_y}) do
    Float.round(:math.sqrt((ship_x - target_x)**2 + (ship_y - target_y)**2), 2)
  end

end
