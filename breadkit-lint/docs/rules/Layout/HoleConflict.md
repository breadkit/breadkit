# Layout/HoleConflict

Only one component lead or supply terminal can occupy a physical hole.

```ruby
resistor :R1, "330", pins: %w[a1 a3]
led :D1, anode: "a1", cathode: "a5"
```

Move one lead to a different hole. Components may still share a conductive strip through separate holes.
