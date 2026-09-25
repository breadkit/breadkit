# frozen_string_literal: true

title "押しボタンで LED を点灯"
board :half

supply :USB, voltage: 5.0, plus: "B+1", minus: "B-1"
net :VCC, at: "B+1"
net :GND, at: "B-1"

button :SW1, at: "e10"
resistor :R1, "330", pins: %w[a12 a16]
led :D1, color: :red, anode: "b16", cathode: "b17"

wire "a10", "B+", color: :red
wire "a17", "B-", color: :black

expect do
  connected "SW1.1", :VCC
  connected "SW1.3", "R1.1"
  connected "R1.2", "D1.anode"
  connected "D1.cathode", :GND
  isolated :VCC, :GND
end
