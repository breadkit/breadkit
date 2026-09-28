# frozen_string_literal: true

title "Light-activated buzzer"
board :half
supply :USB, voltage: 5.0, plus: "B+1", minus: "B-1"
net :VCC, at: "B+1"
net :GND, at: "B-1"

# Use a 5 V active buzzer drawing no more than 20 mA.
part :LDR1, :photoresistor, pins: %w[a6 a9]
resistor :R1, "1k", pins: %w[b9 a12]
pot :VR1, "10k", at: "a14"
transistor :Q1, "2N3904", pins: %w[a17 a18 a19]
part :BZ1, :active_buzzer, pins: %w[a24 a26]
diode :D1, "1N4148", anode: "b26", cathode: "b24"
lint_disable "Electrical/PowerPinUnconnected", on: "BZ1.minus", reason: "Q1 switches the buzzer return"

wire "c6", "B+6", color: :red
wire "c12", "c18", color: :yellow
wire "b12", "c14", color: :yellow
wire "VR1.wiper", "VR1.left", color: :yellow
wire "c16", "B-16", color: :black
wire "c17", "B-17", color: :black
wire "c19", "c26", color: :blue
wire "c24", "B+24", color: :red

expect do
  connected "LDR1.1", :VCC
  connected "LDR1.2", "R1.1"
  connected "R1.2", "VR1.left", "VR1.wiper", "Q1.base"
  connected "VR1.right", :GND
  connected "Q1.emitter", :GND
  connected "Q1.collector", "BZ1.minus"
  connected "BZ1.plus", :VCC
  connected "D1.anode", "Q1.collector"
  connected "D1.cathode", :VCC
  isolated :VCC, :GND
end
