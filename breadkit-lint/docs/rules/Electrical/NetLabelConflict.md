# Electrical/NetLabelConflict

One connected net has multiple distinct labels.

```ruby
net :VCC, at: "B+1"
net :GND, at: "B+2"
```

Check whether the labels or the wiring are wrong, then give the connected net one consistent name.
