defmodule SafetyNetTest do
  use ExUnit.Case
  doctest SafetyNet

  test "start/0" do
    pid = SafetyNet.start()
    {:messages, messages} = Process.info(pid, :messages)
    assert {:init} in messages
  end

end
