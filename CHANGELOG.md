# Changelog

## 0.2.0 — 2026-09-28

### Circuit authoring

- Describe circuits in Ruby, declarative YAML, or TOML. Format declarative files with `breadkit fmt`, reuse Ruby blocks and included files, name bus lines, and record numbered assembly steps.
- Declare intended connections separately from physical wires with `connect`, then use `breadkit suggest` to find available holes for unmet connections.
- Work across named breadboards with IR v2, route a modeled offboard output to power rails, and describe isolated supplies or voltage ranges.
- Declare connection, voltage, and current expectations for selected switch states. Use `breadkit where`, `explain`, `bom`, `diff`, `parts show`, `new`, `doctor`, and `console` to inspect or start a circuit.

### Analysis and electrical models

- Estimate supported DC node voltages, resistor power, and LED or diode currents. The model reports indeterminate results when the required circuit behavior is outside its scope.
- Inspect independent contacts of the four-position C&K BD04 DIP switch as `SW1.1` through `SW1.4`; select combinations explicitly and set a budget for exhaustive switch-state enumeration.
- Use `breadkit patterns FILE` to identify an unloaded two-resistor divider and the documented NE555 astable LED wiring. Divider midpoint voltage is nominal; the 555 result identifies wiring and does not claim a frequency or prove oscillation.
- Report distinct conflicting power terminals, detect shorts from modeled offboard outputs, recognize common ground labels, and retain separate net results for each switch state.
- Parse resistor tolerances and power ratings and capacitor voltage ratings. Part definitions can provide reverse-voltage limits, per-pin current limits, and HTTPS datasheet links.

### Parts and placement

- Add model-specific logic ICs, microcontrollers, displays, switches, sensors, transistors, power connectors, and board footprints. The ShillehTek-style MB102 model requires all four rail holes and selector settings to be specified explicitly.
- Add isolated-pad perfboard, continuous-row stripboard, a 1660-hole breadboard, and custom rails on the top, bottom, left, right, or center of a board.
- Place footprint parts with rotation, mirroring, and millimeter offsets on the 2.54 mm hole grid. Validate optional lead spans and support wires on occupied solder pads where the board permits them.
- Allocate measured jumper lengths and colors from a kit inventory, with explicit results for wires that cannot be assigned.
- Define a part's appearance with `render.svg` metadata for compatible renderers.
- Pin local part and board definitions in `breadkit.lock` with SHA-256 checksums; the separate [breadkit-parts](https://github.com/breadkit/breadkit-parts) repository provides a verified Pico W definition.

### Exports and integrations

- Export KiCad netlists, passive SPICE netlists, supported Wokwi diagrams, and Arduino-style pin constants. The limited Fritzing `.fz` exporter supports a full-size breadboard, wires, resistors, red LEDs, and tact switches, and rejects unsupported parts.
- Inspect data-only circuits through a read-only MCP server, use an LSP server and VS Code preview extension, or try the browser Playground.
- Run explicit circuit files from a build with `Breadkit::RakeTask`. Public part, board, and IR schemas are available on GitHub Pages for editor validation.
- Reject invalid component values, attributes, wire colors, routes, and ambiguous IDs with source locations. Stop runaway Ruby DSL evaluation after a timeout and allow `breadkit ir --force` when diagnostics are present.

## 0.1.0 — 2026-09-26

- Initial release.
