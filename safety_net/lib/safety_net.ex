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
    LighthouseServer.add_ship(state)
    IO.puts("adding ship #{id} to the fleet")
    time_to_move()
    {:ok, state}
  end

  def get_state(pid) do
    GenServer.call(pid, :get_state)
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}

  end

  # ------------------------------- MOVEMENT
  @impl true
  def handle_info(:chopchop, state) do
    %Ship{coords: {old_x, old_y}} = state

    new_x = old_x + Enum.random([0 , 1])
    new_y = old_y + Enum.random([-1 ,0 , 1])
    new_state = %{state | coords: {new_x, new_y}}

    LighthouseServer.update_ship(new_state)
    time_to_move()
    {:noreply, new_state}
  end

  defp time_to_move do
    Process.send_after(self(), :chopchop, 5_000)
  end


  # ---------------------- FIND THE CLOSEST SHIP
  # this assumes the recerived message carries the trigger :search, the state of the sender
  # and the state of the missing ship
  # {:search, sender_distance_vector, missing  -> {id, coords, state}}

  # if sqrt(x1_x2**2 + y1_y2**2) < sender_distance_vector:
  #   send(sender, :ack): Don't worry I'm closer than you
  #   send(:search, next, my_vector, missing): hey, are you closer than me?
  def check_distance do
      GenServer.call(self(), :search)
  end

#  def handle_call(:search, from, state) do

 # end

end




defmodule Demo do

  def initiate do
    LighthouseServer.start_link()

    Process.sleep(100)
    Ship.start_link({1, {1, 1}, :alive})
    Ship.start_link({2, {2, 2}, :alive})
    Ship.start_link({3, {3, 3}, :PIRATES})
  end
end
