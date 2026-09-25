# Electrical/SplitRail

A used segment of a split power rail has no known supply potential while another segment of that rail is powered.

```ruby
board :full, split_rails: true
# Add a wire to B+30 while the supply is attached to B+1.
```

Bridge the rail sections with a wire or attach a supply to each required segment.
