defmodule SafetyNet.PubSub do
  @moduledoc """
  SafetyNet PubSub module
  Provides helpers to broadcast updates and messages to the Lighthouse
  """

  def broadcast(:ship_update, {id, coords, status, incarnation, num_peers}) do
    Phoenix.PubSub.broadcast(Lighthouse.PubSub, "fleet:updates", {:ship_update, %{
      id: id,
      coords: coords,
      status: status,
      incarnation: incarnation,
      peers: num_peers
    }})
  end

  def broadcast(:message, msg) do
    Phoenix.PubSub.broadcast(Lighthouse.PubSub, "fleet:updates", {:message, msg})
  end
end
