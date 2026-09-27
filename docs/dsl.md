# Breadkit DSL

Breadkit evaluates a Ruby file into a breadboard circuit, resolves pin and wire locations, and exposes the result as nets and JSON IR. DSL files are executable Ruby; only load files you trust. Use [YAML or TOML circuit files](DECLARATIVE.md) when the input must remain data-only.

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
| `include(path)` | Evaluate another trusted DSL file in the same circuit. Relative paths resolve from the including file; circular includes are rejected. |
| `block(name) { ... }` / `use_block(name, *args, **kwargs)` | Define and expand a reusable group of DSL declarations. Each name is unique within the circuit. |
| `bus(name, **lines)` | Label the explicit reference for each line as `NAME_LINE`, for example `I2C_SCL`. |
| `step(number, title: nil) { ... }` | Group assembly declarations under a numbered step. Numbers start at 1 and increase by 1. |
| `supply(name, voltage:, plus:, minus:, current_limit: nil)` | Add a DC source. Both terminals occupy board holes. Optional `current_limit:` is the supply's positive output limit in amperes. |
| `net(name, at:)` | Label a hole or component pin. |
| `part(ref, type, value = nil, pins: ..., at: ..., **attrs)` | Place a defined part. `pins:` accepts pin order arrays or pin-name hashes. |
| `wire(from, to, color: nil, id: nil, route: :straight, layer: nil, electrical: true, dashed: false)` | Connect two holes or pin references. `route: :arc` curves the wire; `route: :edge` routes around an outer board edge or from an external module along its terminal row. `layer:` groups wires in interactive SVG output; `electrical: false` draws a visual alternative without changing circuit connectivity. |
| `offboard(name, type, side: :left, at: nil, unused: [], **attrs)` | Place a module beside the board; `at:` aligns its first pin to a board position, and attrs such as `address:` are shown on the module. |
| `expect { ... }` | Declare `connected`, `isolated`, or named `net` expectations. `strict: true` also rejects unlisted pins on declared nets. Use `when: "SW1"` to check a selected switch state. |
| `expect_voltage(ref, range)` / `expect_current(ref, range)` | Declare inclusive DC ranges for a net or component. Current is compared by magnitude in amperes. These methods also work inside `expect(when: "SW1")`. |
| `lint_disable(rule, on: nil, reason: nil)` | Suppress a lint rule, optionally for one target. |

Short forms are available for `resistor`, `capacitor`, `electrolytic`, `diode`, `led`, `transistor`, `pot`, `button`, and `ic`.

## Reusable blocks and buses

A block runs in the same DSL context each time it is used. Pass the references
and holes for each instance explicitly so every component gets a distinct name
and placement:

```ruby
board :mini

block :indicator do |number, resistor_pins:, led_pins:|
  resistor "R#{number}", "330", pins: resistor_pins
  led "D#{number}", color: :red, **led_pins
end

use_block :indicator, 1,
          resistor_pins: %w[a1 a3], led_pins: { anode: "b3", cathode: "b4" }
use_block :indicator, 2,
          resistor_pins: %w[a6 a8], led_pins: { anode: "b8", cathode: "b9" }
```

Blocks defined in an included DSL file are available to the including file.
Recursive calls and duplicate block names are rejected. The resolved circuit
and JSON IR contain the expanded parts and wires, with no separate block
record.

Use a bus to name related nets at their explicit board holes or pin references:

```ruby
bus :I2C, scl: "f22", sda: "f24"
# Creates I2C_SCL at f22 and I2C_SDA at f24.
```

The call adds labels. Add `wire` declarations for physical connections to
devices on each line. The bus helper accepts any named lines; it does not
perform I2C protocol analysis.

## Assembly steps

Place the declarations for each assembly stage inside a numbered `step` block:

```ruby
board :mini

step 1, title: "Install the resistor" do
  resistor :R1, "330", pins: %w[b1 b3]
end

step 2, title: "Add the LED and return wire" do
  led :D1, color: :red, anode: "c3", cathode: "c4"
  wire "d4", "b2", color: :black
end
```

Steps must be declared in order, starting at 1. Nested steps are rejected.
Supplies, net labels, parts, and wires declared inside a step keep that step
number; declarations outside steps have no number. Normal placement and
connectivity checks still apply. `circuit.steps` holds each number and title,
while each resolved item exposes `.step`. JSON IR carries the same `steps`
list and optional `step` field on those items. Existing IR files without steps
remain valid.

## Hole and pin references

- Terminal holes use rows `a` through `j` and 1-based columns, such as `a10` or `J30`.
- Rail holes use `T+`, `T-`, `B+`, and `B-`, optionally followed by a 1-based index. A rail without an index selects the nearest free hole.
- A custom board may define other row and rail IDs in its YAML. For example, rows `u` and `v` use `u1` and `v1`; a rail with `id: PWR` uses `PWR1` or the unindexed `PWR`. Set each rail's `polarity:` to `+` or `-` for polarity-aware rendering.
- Component pins use `R1.1`, `D1.anode`, `U1.8`, or `U1.VCC`. A wire endpoint naming a placed pin selects a free hole in that pin's conductive strip.
- The built-in `ne555` and generic `dip` definitions must straddle the center gap. For a generic package, set `pin_count`, for example `part :U2, :dip, pin_count: 14, at: "e20"`.
- A generic pin header can be sized with `part :J1, :pin_header, pin_count: 4, pins: %w[a1 a2 a3 a4]`.
- Footprint parts accept `rotate: 0|90|180|270` and `mirror: true|false`, for example `part :J1, :pin_header, pin_count: 3, at: "c10", rotate: 90`. Rotation is clockwise on the board; mirroring reflects left to right before rotation. The same orientation is checked when pins are placed explicitly.
- A placed part with `render.size_mm` exposes its physical rectangle as `component.body_bounds(circuit.board)`, in board hole pitch units (`[x, y, width, height]`).
- A custom two-pin part with `placement: leads` may set `max_lead_span_mm` to a positive number. This is the maximum supported distance between the two occupied hole centers after bending its leads. Set it from the actual package and usable lead length; generic built-in parts leave it unspecified. The linter can check placed parts that provide this limit.

Values accept SI suffixes and RKM notation such as `4.7k`, `4k7`, `1M`, `100n`, `10uF`, and `4.7kΩ`.

## Switch states and IR

`circuit.states("none")`, `circuit.states("single")`, and `circuit.states("all")` control switch contact simulation. `Breadkit.load(path)` reads `.bk.rb` DSL, `.bk.yml` / `.bk.yaml` / `.bk.toml` circuit files, or `.json` IR. `circuit.to_ir` returns the resolved circuit representation; automatically selected holes are fixed in IR and are not selected again when loaded.

`old_circuit.diff(new_circuit)` returns a hash of changed board, supply, component, label, and wire entries. Each value is `[before, after]`, with `nil` for an added or removed entry. The CLI `breadkit diff OLD NEW` prints the same changes.

The core CLI provides `breadkit nets`, `breadkit parts`, and `breadkit ir`.

Custom module pins can declare their kind with `type:` in the part YAML, for example `power`, `ground`, `clock`, `data`, `address`, or `interrupt`. The renderer colors typed pin markers and dims pins without a wire connection.

Assign the same `layer:` to wires and components to make them appear together in the interactive SVG layer controls. A layer may be a string or a list of strings when an item belongs to multiple views. Components without a layer remain visible in every view. Use `electrical: false, dashed: true` for an alternate connection that must not affect connectivity analysis.
