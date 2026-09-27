# frozen_string_literal: true

title "LED with current-limiting resistor"
board :half

supply :USB, voltage: 5, plus: "B+1", minus: "B-1"
net :VCC, at: "B+1"
net :GND, at: "B-1"

resistor :R1, "330", pins: %w[a10 a14]
led :D1, color: :red, anode: "b14", cathode: "b16"

wire "c10", "B+", color: :red
wire "a16", "B-", color: :black

expect do
  connected :VCC, "R1.1"
  connected "R1.2", "D1.anode"
  connected "D1.cathode", :GND
  isolated :VCC, :GND
end
