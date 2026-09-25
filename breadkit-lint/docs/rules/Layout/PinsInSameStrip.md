# Layout/PinsInSameStrip

Two pins of the same component share a conductive strip, bypassing the component.

```ruby
resistor :R1, "330", pins: %w[a4 e4]
```

Place the leads in different strips, such as `a4` and `a5`.
