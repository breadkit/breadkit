# frozen_string_literal: true

title "Two-button AND gate"
board :half
supply :USB, voltage: 5.0, plus: "B+1", minus: "B-1"
net :VCC, at: "B+1"
net :GND, at: "B-1"

button :SW1, at: "e4"
button :SW2, at: "e9"
resistor :R1, "10k", pins: %w[a6 a8]
resistor :R2, "10k", pins: %w[a11 a13]
ic :U1, "74HC08", at: "e16", unused: %w[2Y 3Y 4Y]
capacitor :C1, "100n", pins: %w[B+17 B-17]
resistor :R3, "1k", pins: %w[a24 a26]
led :D1, color: :green, anode: "b26", cathode: "b28"

wire "a4", "B+4", color: :red
wire "a9", "B+9", color: :red
wire "B+5", "T+5", color: :red, route: :edge
wire "B-7", "T-7", color: :black, route: :edge
wire "c6", "c16", color: :blue, route: :edge
wire "c11", "c17", color: :yellow, route: :edge
wire "c8", "B-8", color: :black
wire "c13", "B-13", color: :black
wire "U1.VCC", "T+18", color: :red
wire "U1.GND", "B-22", color: :black
wire "U1.1Y", "c24", color: :green
wire "a28", "B-", color: :black

# Unused CMOS inputs need a defined level; their outputs stay unconnected.
%w[2A 2B].each { |input| wire "U1.#{input}", "B-", color: :black }
%w[3A 3B 4A 4B].each { |input| wire "U1.#{input}", "T-", color: :black }

expect do
  connected "SW1.1", :VCC
  connected "SW2.1", :VCC
  connected "SW1.3", "R1.1", "U1.1A"
  connected "SW2.3", "R2.1", "U1.1B"
  connected "R1.2", :GND
  connected "R2.2", :GND
  connected "U1.1Y", "R3.1"
  connected "R3.2", "D1.anode"
  connected "D1.cathode", :GND
  isolated "U1.1A", :VCC
  isolated "U1.1B", :VCC
  isolated :VCC, :GND
end

expect(when: "SW1") do
  connected "U1.1A", :VCC
  isolated "U1.1B", :VCC
end
expect(when: "SW2") do
  connected "U1.1B", :VCC
  isolated "U1.1A", :VCC
end
expect(when: "SW1,SW2") { connected "U1.1A", "U1.1B", :VCC }
