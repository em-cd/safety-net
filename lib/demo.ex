defmodule Demo do

  def init do
    LighthouseServer.start_link()

    Process.sleep(100)

    ships = [:A, :B, :C, :D, :E]

    case Registry.start_link(keys: :unique, name: SafetyNet) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    Enum.each(ships, fn ship_id ->
      case :global.whereis_name(ship_id) do
        :undefined ->
          :ok

        pid when is_pid(pid) ->
          GenServer.stop(pid, :normal)
      end
    end)

    # Start all nodes with peer connections
    {:ok, _} = SafetyNet.start_link(:A, [:B, :C], {1, 1})
    {:ok, _} = SafetyNet.start_link(:B, [:A, :C, :D], {0, 4})
    {:ok, _} = SafetyNet.start_link(:C, [:A, :B, :E], {8, 3})
    {:ok, _} = SafetyNet.start_link(:D, [:B, :E], {3, 7})
    {:ok, _} = SafetyNet.start_link(:E, [:C, :D], {2, 5})

    "Network initialized! 5 ships with different initial data."
  end

  def stop(ship_id) do
    case :global.whereis_name(ship_id) do
      :undefined ->
        {:error, :not_found}

      pid ->
        GenServer.stop(pid)
        {:ok, :stopped}
    end
  end

  def e_missing do
    SafetyNet.check_distance?(%{id: :D, peers: [:B, :E], coords: {3, 7}, status: :alive},%{id: :E, peers: [:C, :D], coords: {2, 5}, status: :missing})
  end

end
