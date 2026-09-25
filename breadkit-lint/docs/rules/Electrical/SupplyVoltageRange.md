# Electrical/SupplyVoltageRange

The known voltage difference between a part's power and ground pins is outside its declared `supply_range`.

```ruby
supply :USB, voltage: 3.3, plus: "B+1", minus: "B-1"
ic :U1, "NE555", at: "e20" # NE555 requires at least 4.5 V
```

Use a valid supply voltage or a part rated for the circuit voltage.
