defmodule SafetyNetTest do
  use ExUnit.Case
  doctest SafetyNet

  test "start/0" do
    pid = SafetyNet.start()
    {:messages, messages} = Process.info(pid, :messages)
    assert {:init} in messages
  end

  test "handler/1, ping" do
    node = node()
    Process.register(self(), :handler)
    pid = spawn(fn -> SafetyNet.handler(Map.new()) end)
    send(pid, {:ping, node})
    assert_receive({:ack, ^node})
  end
end
