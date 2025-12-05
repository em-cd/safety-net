defmodule LighthouseServer do
  @moduledoc """
  LighthouseServer might be written as LHS.
  state = []
  When adding ships, it becomes a list of maps.
  """

  use GenServer

  def start_link do
    IO.puts("Lighthouse starting...")
    GenServer.start_link(LighthouseServer,[], name: :lighthouse)
  end


  @doc """
  Requests to add a ship to the state of the LHS.
   ship : %{id: int, coords: {x,y}, status: :liveness}
  """
  def add_ship(ship) do

    GenServer.cast(:lighthouse, {:add_ship, ship})
  end

  @doc """
  Requests to update the ship's informations on the LHS's state
  """
  def update_ship(ship) do
    GenServer.cast(:lighthouse, {:update, ship})

  end

  @doc """
  Requests the LHS state
  """
  def report, do: GenServer.call(:lighthouse, :report)




  @impl true
  def init(_state) do
    automatic_report()
    {:ok, []}
  end

  # callbacks --------------

  @doc """
  :add_ship -> handles the add_ship function
  :update -> handles all the updates of a ship (coordinates or liveness)
  """
  # ADD SHIP
  @impl true
  def handle_cast({:add_ship, ship}, state) do
    new_state = [ship | state]
    {:noreply, new_state}
  end

  # UPDATE
  @impl true
  def handle_cast({:update, ship}, state) do

    new_state =
      Enum.map(state, fn ship_in_list ->
        if ship_in_list.id == ship.id do

          Map.merge(ship_in_list, ship)

        else
          ship_in_list
        end
      end)
      {:noreply, new_state}
  end

  @doc """
  Handles the REPORT request. (not actually in use)
  """
  @impl true
  def handle_call(:report, _from, state) do
    fleet = state


    {:reply, fleet, state}
  end


  @doc """
  Handles the automatic report printing (a defp).
  Prints out the current list of ships.
  """
  @impl true
  def handle_info(:report, state) do

    fleet = Enum.map(state, fn ship_in_list ->
      %{id: ship_in_list.id,
      coords: ship_in_list.coords,
      status: ship_in_list.status,
      incarnation: ship_in_list.incarnation
    }
    end)

    IO.puts("-------------- REPORT -----------")
    Enum.each(fleet, fn ship_map ->
    IO.puts(inspect(ship_map))
    end)
    IO.puts("-------------- end -----------")
    automatic_report()
    {:noreply, state}
  end


  defp automatic_report do
    Process.send_after(self(), :report, 10_000)
  end
end
