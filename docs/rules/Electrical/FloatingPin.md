# Electrical/FloatingPin

A component pin has no external connection. A pin listed with `unused:` is intentionally ignored.

```ruby
led :D1, anode: "b10", cathode: "b12" # neither pin is wired elsewhere
```

Connect the pin to the intended net or mark a deliberately unused IC pin with `unused:`.
