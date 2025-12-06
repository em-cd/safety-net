# SafetyNet

## Running the code on one terminaò

First start the Mix project in iex:

```bash
iex -S mix
```

You can now initialise a demo with:

```elixir
Demo.init()
```

You should see some pings and acks going back and forth between the processes.

This is the expected output from the Lighthouse:

```
[%Ship{id: 3, coords: {3, 3}, status: :PIRATES}, %Ship{id: 2, coords: {2, 2}, status: :alive}, %Ship{id: 1, coords: {1, 1}, status: :alive}]
```

You can verify the PIDs with:

```iex
GenServer.whereis({:global, 1}) # <- for ships
#PID<0.200.0>

GenServer.whereis(:lighthouse) # <- for the lighthouse
#PID<0.199.0>
```

## Running on different nodes

To create a node

```bash
iex --sname <node_name> --cookie secret  -S mix
```
To connect nodes
```iex
Node.connect(:"node_name@user")
```
To spawn a ship (id, peers, coordinates)
```iex
SafetyNet.start_link(:A, [:B, :C], {1, 1})
```

To spawn the Lighthouse (FRONTEND)
```iex
LighthouseServer.start_link
```

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `safety_net` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:safety_net, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/safety_net>.