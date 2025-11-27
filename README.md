# safety_net

In IEX:

iex(1)> Demo.initiate

Starts the demo by spawning the lighthouse and 3 ships.

____________________
This is the expected output:

[%Ship{id: 3, coords: {3, 3}, status: :PIRATES}, %Ship{id: 2, coords: {2, 2}, status: :alive}, %Ship{id: 1, coords: {1, 1}, status: :alive}]
-------------- end -----------

___________________________________
You can verify the PIDs with:

iex(3)> GenServer.whereis({:global, 1}) <- for ships
#PID<0.200.0>

iex(5)> GenServer.whereis(:lighthouse) <- for the lighthouse
#PID<0.199.0>
