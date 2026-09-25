# Electrical/PowerPinUnconnected

A part pin marked `role: power` or `role: ground` does not reach the matching supply.

```ruby
ic :U1, "NE555", at: "e20" # connect pins 8 and 1 to VCC and GND
```

Connect each required power pin to the corresponding supply rail.
