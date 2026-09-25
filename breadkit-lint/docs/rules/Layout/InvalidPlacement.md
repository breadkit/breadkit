# Layout/InvalidPlacement

A DIP must straddle rows `e` and `f`; a fixed footprint must fit inside the board.

```ruby
ic :U1, "NE555", at: "c20"
```

Place pin 1 on row `e` or `f` and leave enough board space for the full footprint.
