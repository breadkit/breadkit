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
| `breadkit export --format FORMAT FILE` | Export `kicad`, `spice`, `wokwi`, `pins`, or `fritzing` data. |
| `breadkit fmt FILE` | Print a normalized declarative YAML or TOML circuit file. |
| `breadkit lock FILE` | Record the local part and board definition files used by a circuit in `breadkit.lock`. |
| `breadkit suggest FILE` | Print JSON candidates for unmet connection intent between placed pins. Each candidate names two free board holes; nothing is changed. |
| `breadkit kit --inventory KIT.yml FILE` | Allocate candidate jumpers from a measured YAML or JSON inventory. See [Jumper kits](JUMPER_KIT.md). |
| `breadkit patterns FILE` | Print recognized circuit patterns as JSON. An empty array means no supported pattern matched. |
| `breadkit console FILE` | Open IRB with the loaded `circuit` variable. |
| `breadkit doctor` | Check the Ruby version and availability of the optional linter and renderer commands. |

`nets`, `where`, and `explain` accept `--state SWITCH` for a closed switch state.
Their default is the all-open state. A regular switch uses its reference, such
as `SW1`. The C&K BD04 has four independent positions: `SW1.1` through
`SW1.4`. Separate selected positions with commas, for example
`breadkit nets --state SW1.1,SW1.4 circuit.bk.rb`. The position names are
Breadkit logical names, not a claim about the manufacturer's terminal numbers.
`explain` uses DC operating-point analysis for
voltage sources, resistors, LEDs, and diodes. It reports the fixed-drop diode
assumptions and labels ungrounded voltages as relative. Unsupported parts or
indeterminate circuits leave currents unknown. Supply ranges use their midpoint
and resistor tolerances are not propagated into DC current estimates; check
the highest supply voltage and lowest resistance when sizing components.
Library callers can request `circuit.dc_analysis(state, worst_case: true)` to
calculate voltage, current, and resistor power intervals over source voltage
ranges and resistor tolerances. `bounds_status` is `:ok` only when all endpoint
combinations were solved; `:too_complex` means the 512-scenario limit was
reached, and `:indeterminate` means at least one combination could not be
solved. The ordinary `voltages`, `currents`, and `power` fields remain nominal.

`bom` reports quantities, not supplier part numbers or prices. `diff` compares
resolved circuit content and ignores source locations.

`nets`, `where`, `explain`, and `bom` print error diagnostics to standard error
and stop before printing inspection results when the circuit is invalid.
`suggest` follows the same rule. It skips state-specific expectations,
offboard or unplaced pins, occupied holes, holes under component bodies, and
connections that would merge nets with different known voltages.
An empty JSON list means no safe candidate was found; it does not prove the
intent is satisfied. Inspect each candidate before adding a `wire` declaration.

Use `breadkit ir --force FILE` to export a circuit with diagnostics. Supplies
can be marked `isolated: true`, and an inclusive voltage range such as
`3.0..4.2` can describe a battery whose voltage varies. Component values may
also include tolerance or ratings, such as `4.7k 5%`, `330 1/4W`, and
`10u 16V`.

## Circuit patterns

`breadkit patterns FILE` identifies an unloaded two-resistor voltage divider
when exactly one fixed-voltage standalone supply and two resistors form a
series path between its terminals. It uses the DC analysis result for the
nominal midpoint voltage and reports that voltage relative to the supply's
negative terminal. The output names the top and bottom resistors and the
midpoint net:

```sh
breadkit patterns divider.bk.rb
```

The command also recognizes the exact, source-backed NE555 astable wiring used
by [the blinker example](../examples/02_555_blinker.bk.rb): a fixed supply
within the modeled NE555 range; RESET and VCC tied to supply positive; GND tied
to supply negative; TRIG and THR joined; a resistor from VCC to DIS; another
from DIS to TRIG/THR; a correctly polarized timing electrolytic to ground;
control and supply bypass capacitors; and an LED with its series resistor on
OUT. The pin relationships follow the [TI NE555 astable circuit](https://www.ti.com/lit/ds/symlink/ne555.pdf).
The result is labeled `ne555_astable_wiring`: it identifies a connection
pattern, not measured oscillation. No frequency or duty cycle is estimated.
Modified timing, reset, control, or output connections are not classified.

The command prints `[]` when a valid circuit matches neither supported
pattern. Invalid circuits report diagnostics and exit with an error. `[]` does
not mean the circuit is safe or has no useful topology.

## Export formats

| Format | Supported output |
| --- | --- |
| `kicad` | [KiCad XML netlist](https://docs.kicad.org/9.0/en/eeschema/eeschema.html) with resolved component pin numbers and nets. It does not create a schematic or assign PCB footprints. |
| `spice` | [ngspice](https://ngspice.sourceforge.io/docs/ngspice-46-manual.pdf) operating-point netlist for fixed voltage supplies, resistors, and capacitors. Part references must begin with `R` or `C`. Other components and ranged supplies are rejected. |
| `wokwi` | [diagram.json](https://docs.wokwi.com/diagram-format) for Arduino Uno, resistors, and LEDs. Breadboard connections are flattened into wires between part pins. Standalone supplies and unsupported parts are rejected. Add a sketch to simulate it. |
| `pins` | Arduino C header constants for a connected Uno, or MicroPython constants for a connected Pico W / RP2040 board. Label nets to give constants stable signal names. |
| `fritzing` | Native, uncompressed Fritzing `.fz` sketch for the exact built-in 830-hole `full` breadboard, straight electrical jumpers, resistors, red 5 mm LEDs, and 4-pin tact switches. The 50-hole power rails must be unsplit. Resistor and LED leads must share a row; resistor pin 1 must be left of pin 2. Other parts, standalone supplies, net labels, boards, and styled wires are rejected with an error. |

Export stops when the circuit has error diagnostics. `kicad` preserves physical
pin numbers but leaves library and footprint assignment to the KiCad project.

For a supported full-board circuit, run `breadkit export --format fritzing
board.bk.rb > board.fz` and open `board.fz` in Fritzing. The exporter uses
Fritzing's bundled 830-hole breadboard, resistor, red LED, 4-pin pushbutton,
and wire parts. It does not generate a `.fzz` archive or import custom
Fritzing parts. The Fritzing export is available only for the documented
subset; use the renderer for a Breadkit diagram of other circuits. Resistor
values must be plain numbers with an optional engineering suffix (for example,
`330` or `1k`); values with a tolerance, power rating, or `Ω` suffix are
rejected because those properties are not yet preserved in this export.

See the [declarative circuit guide](DECLARATIVE.md) for complete YAML and TOML
examples. The same commands work with any supported circuit input format.
See [locking local definitions](LOCK.md) for the lockfile format and verification behavior.
