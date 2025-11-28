# SafetyNet

## Running the code

First start the Mix project in iex:

```bash
iex -S mix
```

You can now initialise a demo with:

```elixir
Demo.init()
```

You should see some pings and acks going back and forth between the processes.


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

