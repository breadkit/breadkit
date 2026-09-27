# CLI reference

`breadkit` accepts Ruby circuit files (`.bk.rb`) and JSON IR files where a
circuit input is required. Ruby circuit files execute code; load only files you
trust.

| Command | Purpose |
| --- | --- |
| `breadkit new --template led\|555\|arduino [FILE]` | Create a runnable circuit file. The default name is `<template>.bk.rb`; an existing file is never overwritten. |
| `breadkit parts [FILE]` | List built-in parts and definitions loaded by `use_parts` in `FILE`. |
| `breadkit parts show PART [FILE]` | Print a part definition as JSON. |
| `breadkit check-part PART.yml` | Validate one YAML part definition. |
| `breadkit where HOLE FILE` | Show the hole's conductive strip, net, pins, and wire ends. |
| `breadkit explain REF FILE` | Show a component's pins, resolved nets, and constrained potentials. |
| `breadkit bom FILE` | Count parts by type and value, plus jumper wires. |
| `breadkit diff OLD NEW` | List changed board, supplies, labels, components, and wires. |
| `breadkit console FILE` | Open IRB with the loaded `circuit` variable. |
| `breadkit doctor` | Check the Ruby version and availability of the optional linter and renderer commands. |

`where` and `explain` accept `--state SWITCH` for a closed switch state. Their
default is the all-open state. `explain` calculates resistor current when both
terminal potentials are constrained by voltage sources. Other currents and
unanchored net potentials are shown as unknown. `bom` reports quantities, not
supplier part numbers or prices. `diff` compares resolved circuit content and
ignores source locations.

Use `breadkit ir --force FILE` to export a circuit with diagnostics. Supplies
can be marked `isolated: true`, and an inclusive voltage range such as
`3.0..4.2` can describe a battery whose voltage varies.
