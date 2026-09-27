# Jumper kit allocation

Record the usable span of the jumpers you own, measured between the hole
centers they can reach after insertion. Use millimeters and count each color
and size separately:

```yaml
wires:
  - {color: red, usable_span_mm: 12, count: 4}
  - {color: black, usable_span_mm: 20, count: 3}
measured_routes:
  W3: 18
```

Run `breadkit kit --inventory kit.yml circuit.bk.yml`. JSON inventories with
the same structure are accepted. The command prints JSON with `assignments`,
`unassigned`, and `skipped` arrays. Each assignment includes a wire ID, color,
chosen usable span, required span, and its source (`board_geometry` or
`measured`). For a measured route without board geometry, `minimum_span_mm` is
null. Inventory counts
are never reused. A wire with an explicit color only matches the same color;
an uncolored wire can use any inventory color. Color names are compared without
case. The command leaves the circuit and inventory unchanged.

The allocator uses the 2.54 mm terminal-hole geometry of the packaged mini,
half, full, and double-full breadboards. Without a `measured_routes` entry, it
considers only electrical, straight wires between terminal holes on the same
board. It skips rail and offboard endpoints, solder boards, custom boards
without verified pitch, cross-board wires, and curved or edge routes with a
reason in `skipped`. Board spacing in a multi-board diagram is for display and
cannot determine a real cable length.

Use `measured_routes` when you have measured the required usable cable span for
a specific wire, including bends, rise, and the chosen physical route. This
allows a rail, offboard, curved, or cross-board wire to use the kit without
pretending its diagram coordinates are physical measurements. Wire IDs must
exist in the circuit; give such wires explicit `id:` values if declarations
may be reordered. A measured span for a terminal wire cannot be shorter than
the modeled endpoint span. Visual-only wires cannot receive a measured route.

The modeled endpoint span is a lower bound. Routing around components, wire rise,
connector shape, and how the board is mounted can require more length. Measure
`usable_span_mm` with those allowances and inspect each proposed assignment
before building. An `unassigned` entry means the inventory cannot cover an
eligible wire under these constraints; it does not change the circuit.
