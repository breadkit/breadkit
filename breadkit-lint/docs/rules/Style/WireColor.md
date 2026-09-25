# Style/WireColor

A wire attached to a known positive or ground net uses a color outside the configured convention. Defaults are red or orange for positive voltage, and black or blue for ground.

```ruby
wire "a10", "B+", color: :blue
```

Choose a conventional color or set `PositiveColors` / `GroundColors` in `.bklint.yml`.
