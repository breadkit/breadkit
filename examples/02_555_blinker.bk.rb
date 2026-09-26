# frozen_string_literal: true

title "NE555 astable LED blinker"
board :half
supply :USB, voltage: 5.0, plus: "B+1", minus: "B-1"
net :VCC, at: "B+1"
net :GND, at: "B-1"

ic :U1, "NE555", at: "e20"
resistor :R1, "1k", pins: %w[g30 g21]
resistor :R2, "10k", pins: %w[h21 h22]
resistor :R3, "330", pins: %w[a22 a25]
capacitor :C1, "10n", pins: %w[h23 h24]
electrolytic :C2, "100u", plus: "g22", minus: "j24"
led :D1, color: :red, anode: "b25", cathode: "b27"

wire "i30", "B+", color: :red
wire "g20", "B+", color: :red
wire "b20", "B-", color: :black
wire "b21", "i22", color: :yellow
wire "a23", "B+", color: :red
wire "a27", "B-", color: :black
wire "i24", "B-", color: :black

expect do
  connected "U1.1", :GND
  connected "U1.2", "U1.6", "C2.plus"
  connected "U1.4", :VCC
  connected "U1.8", :VCC
  connected "U1.3", "R3.1"
  connected "R3.2", "D1.anode"
  connected "D1.cathode", :GND
  isolated :VCC, :GND
end
