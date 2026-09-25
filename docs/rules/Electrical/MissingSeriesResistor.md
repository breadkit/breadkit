# Electrical/MissingSeriesResistor

An LED has a known unprotected path across a supply. This MVP check uses net reachability and is conservative about complex load branches.

```ruby
led :D1, anode: "b10", cathode: "g12"
wire "a10", "B+"
wire "h12", "B-"
```

Add a current-limiting resistor in series with the LED and verify its two pins land on distinct nets.
