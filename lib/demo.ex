defmodule Demo do

  @doc"""
  Start up a few ships to see SafetyNet in action.
  """
  def init do
    LighthouseServer.start_link()

    ships = [:A, :B, :C, :D, :E]

    # Stop any ships that were already running
    Enum.each(ships, fn ship_id ->
      case :global.whereis_name(ship_id) do
        :undefined ->
          :ok

        pid when is_pid(pid) ->
          GenServer.stop(pid, :normal)
          :global.unregister_name(ship_id)
      end
    end)

    Process.sleep(100)

    # Start all nodes with peer connections
    add_ship(:A, [:B, :C], {1, 1})
    add_ship(:B, [:A, :C, :D], {10, 0})
    add_ship(:C, [:A, :B, :E], {18, 3})
    add_ship(:D, [:B, :E], {14, 30})
    add_ship(:E, [:C, :D], {33, 33})

    "Network initialized! 5 ships with different initial data."
  end


  @doc"""
  Adds a ship
  """
  def add_ship(ship_id, peers, coords \\ {0,0}) do
    {:ok, _} = SafetyNet.start_link(ship_id, peers, coords)
  end

  @doc"""
  Stop a ship. Useful for seeing the failure detection module in action
  """
  def stop(ship_id) do
    case :global.whereis_name(ship_id) do
      :undefined ->
        {:error, :not_found}

      pid ->
        GenServer.stop(pid)
        {:ok, :stopped}
    end
  end

end
