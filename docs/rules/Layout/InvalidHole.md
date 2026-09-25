# Layout/InvalidHole

The reference does not identify a hole on the selected board.

```ruby
wire "k5", "a10" # k is not a breadboard row
```

Use an existing terminal or rail hole, for example `wire "j5", "a10"`.
