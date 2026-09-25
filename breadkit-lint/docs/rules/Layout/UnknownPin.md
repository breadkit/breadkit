# Layout/UnknownPin

A wire, label, or expectation refers to a pin that the component definition does not contain.

```ruby
wire "U1.9", "a10" # NE555 has only pins 1 through 8
```

Check the part pin list and use its pin number or name.
