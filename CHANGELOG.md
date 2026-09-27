# Changelog

## Unreleased

- Preserve a validated HTTPS `datasheet_url` on custom part definitions and in JSON IR.
- Allocate jumpers from a measured color and usable-span inventory, with optional per-wire route measurements and explicit skipped and unassigned results.
- Solve DC current for an explicitly declared `provides` output pin while retaining unknown GPIO state handling for other pins.
- Allow custom part definitions to declare a validated positive `max_current` in amperes on individual pins.
- Suggest explicit free-hole wire endpoints for unmet connection intent without changing circuit wiring.
- Declare layout-independent `connect` intent in Ruby, YAML, and TOML without adding physical wires.
- Reuse fixed circuit connectivity across switch states while keeping each state's nets independent.
- Report a wired power short at its bridge without a duplicate finding on the existing shared return.
- Attach wires to occupied solder pads on universal and stripboard layouts while retaining socket occupancy checks.
- Pin local part and board definition files with SHA-256 checksums in `breadkit.lock`.
- Add isolated-pad universal perfboard and continuous-row stripboard models.
- Report each distinct conflicting power terminal pair, including multiple conflicts involving the same supplies.
- Add an LSP stdio server and a minimal VS Code extension for circuit editing and preview.
- Show circuit errors before printing net and inspection results.
- Add a read-only MCP stdio server for data-only circuit resolution, net inspection, and IR export.
- Route a defined offboard power output and its return to rails with `supply from:`.
- Resolve circuits across named breadboards and preserve board identities in IR v2.
- Accept an optional physical lead-span limit on specific two-pin lead parts.
- Record numbered assembly steps in the Ruby DSL and JSON IR.
- Format declarative YAML and TOML circuit files with `breadkit fmt`.
- Add reusable Ruby DSL blocks and named bus-line labels.
- Read declarative `.bk.yml`, `.bk.yaml`, and `.bk.toml` circuits through the existing resolver without evaluating Ruby.
- Report DSL source lines for evaluation errors and stop runaway circuit files after a timeout.
- Validate component values, part attributes, wire colors and routes, and ambiguous wire IDs.
- Support explicit overrides of built-in parts and warn about unmatched part patterns.
- Preserve stable IR source paths and include board and part schemas.
- Detect shorts from offboard power outputs and recognize common ground labels.
- Allow `breadkit ir --force` to export circuits with diagnostics.
- Add CLI commands for templates, part inspection, circuit lookup, BOM, diff, and an interactive console.
- Support isolated supplies and inclusive voltage ranges in circuit descriptions.
- Export resolved circuits as KiCad XML, passive SPICE netlists, Wokwi diagrams, or firmware pin constants.
- Parse component tolerance, power ratings, and voltage ratings when provided.
- Estimate DC node voltages, resistor power, and LED/diode currents for supported circuits.
- Add model-specific logic ICs, microcontrollers, sensors, switches, displays, power connectors, and breadboard-mounted boards.
- Preserve switch-state expectations in the DSL and IR.
- Evaluate in-memory DSL source against a virtual path for editor integrations.
- Declare expected DC voltage and current ranges in the DSL and IR.

## 0.1.0 — 2026-09-27

- Initial release
