# Changelog

## Unreleased

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

## 0.1.0 — 2026-09-27

- Initial release
