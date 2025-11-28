defmodule Demo do

  def init do
    ships = [:A, :B, :C, :D, :E]

    case Registry.start_link(keys: :unique, name: SafetyNet) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    Enum.each(ships, fn node ->
      case Registry.lookup(SafetyNet, node) do
        [{pid, _}] -> GenServer.stop(pid)
        [] -> :ok
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
end
