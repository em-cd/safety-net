# SafetyNet

## Running the code

First install dependencies and start the Mix project in iex:

```bash
mix deps.get
iex -S mix
```

You can now initialise a demo with:

```elixir
Demo.init()
```

This should initialise a demo with several ships. You will see log messages in the terminal. To simulate a failure, run:

```elixir
Demo.stop(:A)
```

### Adding ships

You can add a new ship with:

```elixir
Demo.add_ship(:ship_id, [:ship_2, :ship_3])
```

By default the new ship's coordinates will be {0,0} but you can also specify them if you like by passing them as
a third argument:

```elixir
Demo.add_ship(:ship_id, [:ship_2, :ship_3], {10,10})
```

You can also add multiple ships at once, for example:

```elixir
Demo.add_ships(10, [:ship_2, :ship_3])
```


## Connecting to the Lighthouse frontend

The [Lighthouse](https://github.com/em-cd/safety-net-lighthouse) is a Phoenix app that uses PubSub to receive broadcasts about the ships and display them.

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


## Running multiple nodes

To create a node:

```bash
iex --sname <node_name> --cookie secret -S mix
```

Now at this point if you have the Lighthouse running, you can simply connect each extra node running SafetyNet to the Lighthouse. They will join the network and be able to communicate with ships on other nodes.

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
