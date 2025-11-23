defmodule SafetyNetTest do
  use ExUnit.Case
  doctest SafetyNet

  test "greets the world" do
    assert SafetyNet.hello() == :world
  end
end
