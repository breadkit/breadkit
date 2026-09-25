# breadkit

`breadkit` provides the Ruby DSL, board and part definitions, connectivity analysis, and JSON IR used by [`breadkit-render`](https://github.com/breadkit/breadkit-render) and [`breadkit-lint`](https://github.com/breadkit/breadkit-lint).

```sh
gem install breadkit
breadkit nets circuit.bk.rb
breadkit ir circuit.bk.rb > circuit.json
breadkit parts
```

Ruby DSL files execute as code. Load only trusted files; use IR JSON for data-only input.

See the [DSL reference](docs/dsl.md) and [project design](docs/DESIGN.md).
