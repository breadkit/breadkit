# Breadkit DSL

Breadkit evaluates a Ruby file into a breadboard circuit, resolves pin and wire locations, and exposes the result as nets and JSON IR. DSL files are executable Ruby; only load files you trust. Use IR JSON when the input must remain data-only.

## A small circuit

```ruby
title "Button controlled LED"
board :half
supply :USB, voltage: 5, plus: "B+1", minus: "B-1"
net :VCC, at: "B+1"
net :GND, at: "B-1"

button :SW1, at: "e10"
resistor :R1, "330", pins: %w[a12 a16]
led :D1, color: :red, anode: "b16", cathode: "b17"
wire "a10", "B+", color: :red
wire "a17", "B-", color: :black

expect do
  connected "SW1.1", :VCC
  isolated :VCC, :GND
end
```

## Declarations

| Method | Purpose |
| --- | --- |
| `title(text)` | Diagram title. |
| `board(id, split_rails: false)` | Select `:full`, `:half`, `:mini`, or a custom board ID. |
| `use_parts(path)` / `use_boards(path)` | Load additional YAML definitions relative to the DSL file. Paths may use globs. |
| `supply(name, voltage:, plus:, minus:)` | Add a DC source. Both terminals occupy board holes. |
| `net(name, at:)` | Label a hole or component pin. |
| `part(ref, type, value = nil, pins: ..., at: ..., **attrs)` | Place a defined part. `pins:` accepts pin order arrays or pin-name hashes. |
| `wire(from, to, color: nil, id: nil, route: :straight)` | Connect two holes or pin references. `route: :arc` curves the drawn wire. |
| `offboard(name, type, side: :left)` | Add a module such as `"arduino_uno"`; connect it with pin references like `"UNO.D13"`. |
| `expect { ... }` | Declare `connected`, `isolated`, or named `net` expectations. `strict: true` also rejects unlisted pins on declared nets. |
| `lint_disable(rule, on: nil, reason: nil)` | Suppress a lint rule, optionally for one target. |

Short forms are available for `resistor`, `capacitor`, `electrolytic`, `diode`, `led`, `transistor`, `pot`, `button`, and `ic`.

## Hole and pin references

- Terminal holes use rows `a` through `j` and 1-based columns, such as `a10` or `J30`.
- Rail holes use `T+`, `T-`, `B+`, and `B-`, optionally followed by a 1-based index. A rail without an index selects the nearest free hole.
- Component pins use `R1.1`, `D1.anode`, `U1.8`, or `U1.VCC`. A wire endpoint naming a placed pin selects a free hole in that pin's conductive strip.
- The built-in `ne555` and generic `dip` definitions must straddle the center gap. For a generic package, set `pin_count`, for example `part :U2, :dip, pin_count: 14, at: "e20"`.
- A generic pin header can be sized with `part :J1, :pin_header, pin_count: 4, pins: %w[a1 a2 a3 a4]`.

Values accept SI suffixes and RKM notation such as `4.7k`, `4k7`, `1M`, `100n`, `10uF`, and `4.7kΩ`.

## Switch states and IR

`circuit.states("none")`, `circuit.states("single")`, and `circuit.states("all")` control switch contact simulation. `Breadkit.load(path)` reads `.bk.rb` DSL or `.json` IR. `circuit.to_ir` returns the resolved circuit representation; automatically selected holes are fixed in IR and are not selected again when loaded.

The core CLI provides `breadkit nets`, `breadkit parts`, and `breadkit ir`.
