defmodule SafetyNet.ShipMovement do
  @moduledoc """
  Ship movement module
  """

  @doc"""
  Update x and y coordinates
  """
  def move({old_x, old_y}) do
    new_x = old_x + Enum.random([-1, 0 , 1])
    new_y = old_y + Enum.random([-1 ,0 , 1])

    # Bound the new coordinates to prevent going out of bounds
    max_x = 33
    max_y = 33
    new_x = max(0, min(max_x, new_x))
    new_y = max(0, min(max_y, new_y))

    {new_x, new_y}
  end
end
