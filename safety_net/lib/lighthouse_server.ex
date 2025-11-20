defmodule LighthouseServer do
  use GenServer

  def start_link() do
    IO.puts("Lighthouse starting...")
    GenServer.start_link(LighthouseServer,%{}, name: :lighthouse)
  end

  def add_ship(id, position, liveness) do
  GenServer.cast(:lighthouse, {:add_ship, %{id: id, coords: position,status: liveness}})
  end

  @impl true
  def init(_state) do
    {:ok, %{id: nil, coords: {}, status: :nil}}
  end

  # handle_cast receives from the fleet and sends to
  @impl true
  def handle_cast({ship_id, coordinates, liveness}, _state) do
    new_state = %{id: ship_id, coords: coordinates, status: liveness}
    {:noreply, new_state}
  end

  @impl true
  def handle_call(:report, _from, state) do

    {:reply, state}
  end
end
