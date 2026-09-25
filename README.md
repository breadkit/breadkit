# breadkit

`breadkit` provides the shared DSL, board and part definitions, connectivity analysis, and JSON IR used by `breadkit-render` and `breadkit-lint`.

```sh
gem install breadkit
breadkit nets circuit.bk.rb
breadkit ir circuit.bk.rb > circuit.json
breadkit parts
```

DSL input is executable Ruby. Use only trusted `.bk.rb` files; IR JSON is the data-only alternative.

The full project guide and [DSL reference](../docs/dsl.md) are maintained at the repository root.
