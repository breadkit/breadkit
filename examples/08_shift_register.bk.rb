# frozen_string_literal: true

title "Arduino 74HC595 LED sequencer"
board :half
# Drive D8 (data), D9 (shift clock), and D10 (latch clock) in firmware.
offboard :UNO, :arduino_uno, side: :left
supply from: "UNO.5V", plus: "B+1", minus: "B-1"
net :VCC, at: "B+1"
net :GND, at: "B-1"

ic :U1, "74HC595", at: "e8", unused: %w[QA QF QG QH QH_SERIAL]
capacitor :C1, "100n", pins: %w[B+16 B-16]

wire "B+4", "T+4", color: :red, route: :edge
wire "B-5", "T-5", color: :black, route: :edge
wire "U1.VCC", "T+8", color: :red
wire "U1.GND", "B-12", color: :black
wire "U1.SRCLR", "T+14", color: :red
wire "U1.OE", "T-11", color: :black
wire "UNO.D8", "U1.SER", color: :blue, route: :edge
wire "UNO.D9", "U1.SRCLK", color: :green, route: :edge
wire "UNO.D10", "U1.RCLK", color: :yellow, route: :edge

%w[QB QC QD QE].each_with_index do |output, index|
  column = 19 + index * 3
  resistor :"R#{index + 1}", "1k", pins: ["a#{column}", "a#{column + 1}"]
  led :"D#{index + 1}", color: [:red, :yellow, :green, :blue][index],
      anode: "b#{column + 1}", cathode: "b#{column + 2}"
  wire "U1.#{output}", "c#{column}", color: :orange
  wire "a#{column + 2}", "B-", color: :black
end

expect do
  connected "U1.VCC", :VCC
  connected "U1.GND", :GND
  connected "U1.SRCLR", :VCC
  connected "U1.OE", :GND
  connected "UNO.D8", "U1.SER"
  connected "UNO.D9", "U1.SRCLK"
  connected "UNO.D10", "U1.RCLK"
  %w[QB QC QD QE].each_with_index do |output, index|
    connected "U1.#{output}", "R#{index + 1}.1"
    connected "R#{index + 1}.2", "D#{index + 1}.anode"
    connected "D#{index + 1}.cathode", :GND
  end
  isolated :VCC, :GND
end
