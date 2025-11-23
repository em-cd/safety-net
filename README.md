# SafetyNet

## Running the code

To try out SafetyNet, you will need at least two remote nodes that will communicate with each other. Open a terminal and start a node in a Beam VM:

```bash
iex --sname node1 --cookie secret -S mix
```

Open a second terminal and start a second node:

```bash
iex --sname node2 --cookie secret -S mix
```

Now we need to connect the two. In the the first terminal, enter:

```elixir
Node.connect(:"node2@hostname")
Node.list()
```

If the nodes were successfully connected, you should see the other node's name appear in the list. If you aren't sure about the node hostname, you can type `Node.self()` inside the IEX shell to see a node's name and hostname.

Now your nodes are connected, start the application in each node's terminal:

```elixir
SafetyNet.start()
```

You should now see some pings and acks going back and forth between the nodes.


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

