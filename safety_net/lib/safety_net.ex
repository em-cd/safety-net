defmodule Core do
def initiate do
  LighthouseServer.start_link()

  LighthouseServer.add_ship(%{id: 1, status: :alive, coords: {0, 0}})
  LighthouseServer.add_ship(%{id: 2, status: :alive, coords: {0, 1}})
  LighthouseServer.add_ship(%{id: 3, status: :alive, coords: {1, 0}})
  LighthouseServer.add_ship(%{id: 4, status: :alive, coords: {1, 1}})
end


end
