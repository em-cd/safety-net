defmodule Ship do
  use GenServer

  defstruct  id: nil, coords: {0, 0}, status: :alive


  # in IEX: Ship.start_link({number_or_name, {x,y}, :atom}) <- has to be passed as a tuple
  def start_link({id, coords, status}) do
    IO.puts("Ship spawning")
    GenServer.start_link(Ship, {id, coords, status}, [name: {:global, id}])
  end

  @impl true
  def init({id, coordinates, status}) do
    state = %__MODULE__{
      id: id,
      coords: coordinates,
      status: status
    }

    {:ok, state}
  end

  def get_state(pid) do
    GenServer.call(pid, :get_state)
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}

  end
end





defmodule Core do
def initiate do
  LighthouseServer.start_link()

  LighthouseServer.add_ship(%{id: 1, status: :alive, coords: {0, 0}})
  LighthouseServer.add_ship(%{id: 2, status: :alive, coords: {0, 1}})
  LighthouseServer.add_ship(%{id: 3, status: :alive, coords: {1, 0}})
  LighthouseServer.add_ship(%{id: 4, status: :alive, coords: {1, 1}})
end


end
