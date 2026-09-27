# CLI reference

`breadkit` accepts Ruby circuit files (`.bk.rb`), declarative YAML
(`.bk.yml`, `.bk.yaml`) and TOML (`.bk.toml`) circuit files, and JSON IR files
where a circuit input is required. Ruby circuit files execute code; load only
files you trust. YAML and TOML circuit files are parsed as data. Ordinary `.yml`
part definitions are not circuit inputs.

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
| `breadkit export --format FORMAT FILE` | Export `kicad`, `spice`, `wokwi`, or `pins` data. |
| `breadkit fmt FILE` | Print a normalized declarative YAML or TOML circuit file. |
| `breadkit console FILE` | Open IRB with the loaded `circuit` variable. |
| `breadkit doctor` | Check the Ruby version and availability of the optional linter and renderer commands. |

`where` and `explain` accept `--state SWITCH` for a closed switch state. Their
default is the all-open state. `explain` uses DC operating-point analysis for
voltage sources, resistors, LEDs, and diodes. It reports the fixed-drop diode
assumptions and labels ungrounded voltages as relative. Unsupported parts or
indeterminate circuits leave currents unknown. `bom` reports quantities, not
supplier part numbers or prices. `diff` compares resolved circuit content and
ignores source locations.

`nets`, `where`, `explain`, and `bom` print error diagnostics to standard error
and stop before printing inspection results when the circuit is invalid.

Use `breadkit ir --force FILE` to export a circuit with diagnostics. Supplies
can be marked `isolated: true`, and an inclusive voltage range such as
`3.0..4.2` can describe a battery whose voltage varies. Component values may
also include tolerance or ratings, such as `4.7k 5%`, `330 1/4W`, and
`10u 16V`.

## Export formats

| Format | Supported output |
| --- | --- |
| `kicad` | [KiCad XML netlist](https://docs.kicad.org/9.0/en/eeschema/eeschema.html) with resolved component pin numbers and nets. It does not create a schematic or assign PCB footprints. |
| `spice` | [ngspice](https://ngspice.sourceforge.io/docs/ngspice-46-manual.pdf) operating-point netlist for fixed voltage supplies, resistors, and capacitors. Part references must begin with `R` or `C`. Other components and ranged supplies are rejected. |
| `wokwi` | [diagram.json](https://docs.wokwi.com/diagram-format) for Arduino Uno, resistors, and LEDs. Breadboard connections are flattened into wires between part pins. Standalone supplies and unsupported parts are rejected. Add a sketch to simulate it. |
| `pins` | Arduino C header constants for a connected Uno, or MicroPython constants for a connected Pico W / RP2040 board. Label nets to give constants stable signal names. |

Export stops when the circuit has error diagnostics. `kicad` preserves physical
pin numbers but leaves library and footprint assignment to the KiCad project.

See the [declarative circuit guide](DECLARATIVE.md) for complete YAML and TOML
examples. The same commands work with any supported circuit input format.
