# Electrical/NoCommonGround

Multiple power supplies belong to disconnected supply-reference groups.

```ruby
supply :A, voltage: 5, plus: "B+1", minus: "B-1"
supply :B, voltage: 3.3, plus: "T+1", minus: "T-1"
```

Connect the grounds when the powered circuits exchange signals or current.
