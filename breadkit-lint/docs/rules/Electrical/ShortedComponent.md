# Electrical/ShortedComponent

A two-pin component's pins resolve to the same net, so current can bypass the component.

```ruby
resistor :R1, "330", pins: %w[a4 e4]
```

Move the pins to separate strips and verify the resulting net list.
