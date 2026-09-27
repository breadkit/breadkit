# YAML and TOML circuit files

Use `.bk.yml` or `.bk.yaml` for YAML and `.bk.toml` for TOML. Breadkit parses
these files as data and passes their declarations through the same builder and
resolver used by the Ruby DSL. Ordinary `.yml` files remain part definitions.

Try the complete [YAML](../examples/06_declarative_led.bk.yml) and
[TOML](../examples/07_declarative_led.bk.toml) LED examples:

```sh
breadkit nets examples/06_declarative_led.bk.yml
breadkit ir examples/07_declarative_led.bk.toml > circuit.json
breadkit fmt examples/06_declarative_led.bk.yml > formatted.bk.yml
```

The YAML example describes a USB supply, resistor, LED, jumper wire, and three
expected connections:

```yaml
title: LED circuit
board: mini
supplies:
  - {name: USB, voltage: 5, plus: a1, minus: a2}
labels:
  - {name: VCC, at: a1}
  - {name: GND, at: a2}
parts:
  - {ref: R1, type: resistor, value: "330", pins: [b1, b3]}
  - {ref: D1, type: led, pins: {anode: c3, cathode: c4}, attrs: {color: red}}
wires:
  - {from: d4, to: b2, color: black}
expectations:
  - connected: [[VCC, R1.1], [R1.2, D1.anode], [D1.cathode, GND]]
```

## Fields

| Field | Shape | Meaning |
| --- | --- | --- |
| `title` | text | Circuit title. |
| `board` | text or mapping | Board type, optionally `{type: full, split_rails: true}`. |
| `boards` | list of mappings | Named boards with `name`, `type`, and optional `split_rails`; use instead of `board`. Qualify holes as `B1.a1`. |
| `use_parts`, `use_boards` | path or list of paths | Load definitions relative to the circuit file. Globs are accepted. |
| `supplies` | list of mappings | Either `name`, `voltage`, `plus`, `minus` for a standalone source, or `from`, `plus`, `minus` to route a defined offboard output. Standalone sources also accept `isolated` and numeric `current_limit`. |
| `labels` | list of mappings | `name` and `at` for a named net. |
| `parts` | list of mappings | `ref`, `type`; optional `value`, `pins`, `at`, `attrs`, `unused`. |
| `offboard` | list of mappings | `ref`, `type`; optional `side`, `at`, `attrs`, `unused`. `offboard: true` also works in a `parts` entry. |
| `wires` | list of mappings | `from`, `to`; optional `color`, `id`, `route`, `layer`, `electrical`, `dashed`. |
| `expectations` | list of mappings | Optional `strict`, `when`, and connection, isolation, net, voltage, or current checks. |
| `lint_disables` | list of mappings | `rule`; optional `on` and `reason`. |

Quote `"on"` when using that key in YAML, because YAML parsers may interpret
an unquoted `on` as a boolean.

Use a list for positional part pins (`pins: [b1, b3]`) or a mapping for named
pins (`pins: {anode: c3, cathode: c4}`). `attrs` holds part-specific options,
such as `color`, `rotate`, or `mirror`. Supply voltage can be a number, a value
string such as `3.3V`, or an inclusive range string such as `3.0..4.2`. Part
values accept the same notation as the Ruby DSL, including `4.7k 5%`,
`330 1/4W`, and `10u 16V`.

An expectation can contain `connected` or `isolated` as lists of reference
lists, `nets` as a list of `{name, refs}` mappings, and `voltage` or `current`
as lists of `{ref, range}` mappings. Measurement ranges use inclusive strings
such as `"3.0..3.6"`. `when` names a switch state. Example:

```yaml
expectations:
  - strict: true
    connected: [[VCC, R1.1]]
    isolated: [[VCC, GND]]
    nets: [{name: VCC, refs: [R1.1]}]
    voltage: [{ref: VCC, range: "4.8..5.2"}]
```

For TOML, use a `[[section]]` array of tables for each list entry. The
[complete TOML example](../examples/07_declarative_led.bk.toml) shows this
structure. For a custom offboard module, define its part in YAML and load it
with `use_parts`:

```yaml
board: mini
use_parts: [sensor.yml]
offboard:
  - {ref: SENSOR, type: sensor, side: left}
wires:
  - {from: SENSOR.SIG, to: a1}
```

YAML object tags and aliases are rejected. Unknown fields and invalid field
types produce input errors. Diagnostics from declarative files currently point
to the file's first line rather than the individual field.

For multiple boards, use `boards` instead of `board`:

```yaml
boards:
  - {name: B1, type: half}
  - {name: B2, type: mini}
wires:
  - {from: B1.a1, to: B2.j1}
```

This produces version 2 IR. See the [DSL reference](dsl.md#multiple-boards)
for board identity and connection rules.

An offboard output can feed rails without declaring a duplicate voltage source:

```yaml
board: half
offboard:
  - {ref: UNO, type: arduino_uno}
supplies:
  - {from: UNO.5V, plus: T+, minus: T-}
```

The output voltage and return pin come from the part's `provides` definition.
Both rail destinations are required, and the resolved IR contains two wires.

`breadkit fmt FILE` prints canonical YAML or TOML without modifying the input.
It validates the circuit fields first and keeps the original format. Formatting
discards comments, so review the output before replacing a commented source
file. Ruby DSL files are not supported by this formatter.
