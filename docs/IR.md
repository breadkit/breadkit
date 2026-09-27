# JSON circuit IR

Breadkit IR is a resolved circuit in JSON. Generate it from a circuit file to
pass the same circuit to Breadkit, breadkit-render, breadkit-lint, or another
tool. JSON input is data-only; Ruby DSL input executes code.

```sh
breadkit ir examples/06_declarative_led.bk.yml > circuit.json
breadkit nets circuit.json
```

Here is a compact, valid v1 IR input for a circuit using built-in definitions:

```json
{
  "schema_version": 1,
  "title": "LED circuit",
  "board": { "type": "mini", "options": { "split_rails": false } },
  "supplies": [
    { "name": "USB", "voltage": 5, "plus": "a1", "minus": "a2", "source": null }
  ],
  "labels": [],
  "components": [
    { "ref": "R1", "part": "resistor", "value": "330", "attrs": {},
      "pins": { "1": "b1", "2": "b3" }, "unused": [], "source": null },
    { "ref": "D1", "part": "led", "value": null, "attrs": { "color": "red" },
      "pins": { "anode": "c3", "cathode": "c4" }, "unused": [], "source": null }
  ],
  "wires": [
    { "id": "W1", "from": "d4", "to": "b2", "color": null,
      "route": "straight", "source": null }
  ],
  "expectations": []
}
```

`breadkit ir` writes additional resolved details, including the board
definition, any custom part definitions, source locations, and `analysis.nets`.
The reader recalculates `analysis` when loading IR. Use
[IR v1](../schema/ir-v1.json) for one unnamed board and
[IR v2](../schema/ir-v2.json) for named boards. See the
[compatibility policy](COMPATIBILITY.md) before consuming IR in another tool.
