# Layout/DuplicateRef

Component references and wire IDs must be unique within a circuit.

```ruby
resistor :R1, "330", pins: %w[a1 a3]
resistor :R1, "1k", pins: %w[a5 a7]
```

Give each component and explicitly named wire a distinct identifier.
