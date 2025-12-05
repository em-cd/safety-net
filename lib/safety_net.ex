defmodule SafetyNet do
  @moduledoc """
  Documentation for `SafetyNet`.
  """
  use GenServer
  defstruct [:id, :peers, :coords, :status]

  def start_link(id, peers \\ [], coords \\ {0, 0}, status \\ :alive) do
    GenServer.start_link(__MODULE__, {id, peers, coords, status}, name: {:global, id})
  end

  @impl true
  def init({id, peers, coords, status}) do
    state = %__MODULE__{
      id: id,
      peers: peers,
      coords: coords,
      status: status
    }

    LighthouseServer.add_ship(state)
    schedule_probe()
    #time_to_move()

    {:ok, state}
  end

  @doc """
  Once a ship is defined as MISSING, one ship calls this function to start looking for the closest ship.
  This functions creates a cascade where ships compare their distances between peers and find the closest one.
  It changes the participating ships statuses in:
  :visited -> to mark the ones already compared
  :closest -> temporary identifying the closest one
  :search -> appears after a timer runs down and it identifies the final closest ship
  :alive -> In case the missing ship is actually alive, it will set its status back to alive. No other action has been set.
  """
  def check_distance?(my_state, missing_ship) do
    IO.puts("I, #{my_state.id}, think #{missing_ship.id} is missing")

    # calculate my distace from missing ship
    my_distance = calculate_distance(my_state.coords, missing_ship.coords)
    IO.puts("I'm #{my_distance} clicks far away")
    # set status: :closest
    GenServer.cast({:global, my_state.id}, {:update_state, :closest})

    ask_peers(my_state, missing_ship, my_distance)
   end


  # ---------------------------------------- HANDLE INFOS
  @doc """
  :probe -> Pick a random peer and ping them
  :ack -> Prints receiving an ACK
  :search -> after wait() if the ship is still the closest to the missing one, sets its status to :search
  :chopchop -> makes the ships move . It's called by time_to_move()

  """
  # Ping a random peer
  @impl true
  def handle_info(:probe, state) do
    if state.peers != [] do
      peer = Enum.random(state.peers)
      GenServer.cast({:global ,peer}, {:ping, state.id, self()})
    end

    schedule_probe()
    {:noreply, state}
  end

  # Print receiving an ACK
  @impl true
  def handle_info({:ack, from}, state) do
    #IO.puts("#{state.id}: received ack from #{from}")
    {:noreply, state}
  end

  @impl true
  def handle_info(:search, state) do
    if state.status == :closest do
      GenServer.cast({:global, state.id}, {:update_state, :search})
      {:noreply, state}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(:chopchop, state) do
    %SafetyNet{coords: {old_x, old_y}} = state

    new_x = old_x + Enum.random([0 , 1])
    new_y = old_y + Enum.random([-1 ,0 , 1])
    new_state = %{state | coords: {new_x, new_y}}

    LighthouseServer.update_ship(new_state)
    time_to_move()
    {:noreply, new_state}
  end

#-------------------------------------------- HANDLE CASTS
@doc """
:ping -> Receive a PING, send ACK back
:closer? -> called by check_distance/2
:update_state -> to change status in a state. Please pass a new status to the function.
NOTE: If the new status is :closest, it starts a timer to confirm it and turn it into :search
"""

  @impl true
  def handle_cast({:ping, from_id, from_pid}, state) do
    IO.puts("#{state.id}: received ping from #{from_id}, sending ack")
    send(from_pid, {:ack, state.id})
    {:noreply, state}
  end


  @impl true
  def handle_cast({:closer?,{ missing, d, closest_ship}}, my_state) do
    cond do
      my_state.id == missing.id ->
      IO.puts("Hey, i'm alive!")
      GenServer.cast({:global,my_state.id}, {:update_state, :alive})
      {:noreply, my_state}


    my_state.status == :visited ->
      IO.puts("You've already asked me")
      {:noreply, my_state}

    true ->
          # set stat to visited
      GenServer.cast({:global,my_state.id}, {:update_state, :visited})

      # calculate distance
      distance = calculate_distance(my_state.coords, missing.coords)
      IO.puts("#{my_state.id}: I'm at #{distance} clicks")

      # compare distance
      if distance <= d do
        IO.puts("#{my_state.id}: I'm closer")
        GenServer.cast({:global, my_state.id}, {:update_state, :closest})
        GenServer.cast({:global,closest_ship.id}, {:update_state, :visited})

        ask_peers(my_state, missing, distance)

      else
        IO.puts("#{my_state.id}: I'm too far. I'll ask around")

        ask_peers(my_state, missing, d)
        end
      {:noreply, my_state}
    end
  end


  @impl true
  def handle_cast({:update_state, new}, state) do
    new_state = %{state | status: new}
    IO.puts("#{new_state.id} ----> STATUS: #{new_state.status}")
    LighthouseServer.update_ship(new_state)
    if new == :closest do
      wait()
    end
    {:noreply, new_state}
  end


  # ------------------------------------------- HELPERS

  defp schedule_probe do
    Process.send_after(self(), :probe, 5000)
  end

  defp time_to_move do
    Process.send_after(self(), :chopchop, 5_000)
  end

  defp via(id), do: {:via, Registry, {SafetyNet, id}}

  defp wait do
    Process.send_after(self(), :search, 5_000)
  end

  defp calculate_distance({ship_x, ship_y}, {target_x, target_y}) do
   :math.sqrt((ship_x - target_x)**2 + (ship_y - target_y)**2)
  end

  defp ask_peers(my_state, missing_ship, my_distance) do
    Enum.each(my_state.peers, fn ship_id ->

    GenServer.cast({:global,ship_id}, {:closer?, {missing_ship, my_distance, my_state}}) end)
  end


end
