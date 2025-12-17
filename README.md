# SafetyNet

## Running the code on one terminal

First install dependencies and start the Mix project in iex:

```bash
mix deps.get
iex -S mix
```

You can now initialise a demo with:

```elixir
Demo.init()
```

This should initialise a demo with several ships. To simulate a failure, run:

```elixir
Demo.stop(:A)
```

You can also add a new ship with:

```elixir
Demo.add_ship(:ship_id, [:ship_2, :ship_3])
```

By default the new ship's coordinates will be {0,0} but you can also specify them if you like by passing them as
a third argument:

```elixir
Demo.add_ship(:ship_id, [:ship_2, :ship_3], {10,10})
```

## Connecting to the Lighthouse frontend

The Lighthouse is a Phoenix app that uses PubSub to receive broadcasts about the ships and display them.

Start the Lighthouse with a cookie and a node name, e.g.:

```bash
iex --name lighthouse@localhost --cookie secret -S mix phx.server
```

Now when you start the SafetyNet app, use the same cookie:

```bash
iex --name <node_name> --cookie secret -S mix
```

Then connect SafetyNet to the Lighthouse by running:

```elixir
Node.connect(:lighthouse@localhost)
```

Now the nodes should be connected. You can start the demo and the ships will broadcast updates to the Lighthouse automatically.


## Running on different nodes

To create a node:

```bash
iex --sname <node_name> --cookie secret -S mix
```

Now at this point if you have the Lighthouse running, you can simply connect each extra node running SafetyNet to the Lighthouse and they will join the network and be able to communicate with ships on other nodes.

If you aren't running the Lighthouse, simply connect nodes to each other:

```elixir
Node.connect(:"node_name@user")
```

To run a distributed demo, run `Demo.init()` in one terminal and in the other add some ships:

```elixir
Demo.add_ship(:F, [:B, :C], {1, 1})
Demo.add_ship(:G, [:A])
```

## Running tests

There are a few tests, you can run them with the following command:

```bash
mix test
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