# Intent/ConnectionMismatch

Actual connectivity differs from a declared `connected`, `isolated`, or `net` expectation.

```ruby
expect { connected "R1.1", "D1.anode" }
```

Correct the wiring or update the expectation to match the intended circuit. `strict: true` also rejects extra pins on a declared net.
