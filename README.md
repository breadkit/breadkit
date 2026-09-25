# Breadkit

Breadkit is the shared Ruby core for describing breadboard layouts, resolving connections, and exporting a JSON circuit representation. It requires Ruby 3.3 or newer and has no runtime gem dependencies.

```ruby
title "LED with a push button"
board :half
supply :USB, voltage: 5, plus: "B+1", minus: "B-1"
net :VCC, at: "B+1"
net :GND, at: "B-1"

button :SW1, at: "e10"
resistor :R1, "330", pins: %w[a12 a16]
led :D1, color: :red, anode: "b16", cathode: "b17"
wire "a10", "B+"
wire "a17", "B-"
```

Load a DSL file or an IR JSON file from Ruby:

```ruby
require "breadkit"
circuit = Breadkit.load("circuit.bk.rb")
circuit.diagnostics
circuit.nets
File.write("circuit.json", JSON.pretty_generate(circuit.to_ir))
```

The core CLI prints resolved nets or IR:

```sh
bundle exec exe/breadkit nets circuit.bk.rb
bundle exec exe/breadkit ir circuit.bk.rb
```

`*.bk.rb` files execute as Ruby code. Only load files you trust. Use IR JSON for data-only input.

See [the design](../.idea/DESIGN.md) for the full DSL and architecture plan. Rendering and linting are provided by the sibling `breadkit-render` and `breadkit-lint` gems.
