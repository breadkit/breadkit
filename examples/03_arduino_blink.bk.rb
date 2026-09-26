title "Arduino UNO LED"
board :half
offboard :UNO, "arduino_uno", side: :left

resistor :R1, "330", pins: %w[a10 a14]
led :D1, color: :red, anode: "b14", cathode: "b16"

wire "UNO.D13", "c10", color: :yellow
wire "a16", "UNO.GND", color: :black

expect do
  connected "UNO.D13", "R1.1"
  connected "R1.2", "D1.anode"
  connected "D1.cathode", "UNO.GND"
end
