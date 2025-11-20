defmodule LighthouseServer do
  # "LighthouseServer" might be written as "LHS" in the comments
  use GenServer

  def start_link do
    IO.puts("Lighthouse starting...")
    GenServer.start_link(LighthouseServer,[], name: :lighthouse)
  end

  def add_ship(ship) do
    #at spawn, each ship has to run this to be added to the LHS
    GenServer.cast(:lighthouse, {:add_ship, ship})
  end

  def report, do: GenServer.call(:lighthouse, :report)

  @impl true
  def init(_state) do
    # The initial_state is an empty list
    # in which maps (id/coords/status) are added.
    # This way, each map identifies a ship and its state,
    # whilest the LHS-list will effectively represent the fleet's states

    # %{id: id, coords: {x, y}, status: :nil} <- SHIP'S STATE
    # [ship1, ship2...] <- LHS state

    {:ok, []}
  end

  # handle_cast receives from the fleet and sends to
  @impl true
  def handle_cast({:add_ship, ship}, state) do
    new_state = [ship | state]
    {:noreply, new_state}
  end

  @impl true
  def handle_call(:report, _from, state) do
    fleet = state
    {:reply, fleet, state}
  end
end
