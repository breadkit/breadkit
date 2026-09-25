# Electrical/ReversePolarity

The positive pin of a polarized part is at a lower known potential than its negative pin.

```ruby
led :D1, anode: "b10", cathode: "g12"
# Connect anode to GND and cathode to VCC.
```

Swap the connections so the positive pin faces the higher potential.
