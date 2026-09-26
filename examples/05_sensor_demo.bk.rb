title "Sensor demo · RP2040 + OLED + 2×SHT31 + switches + IR"
board :full
use_parts "parts/*.yml"

# The 3.3 V source represents the board regulator; USB power is outside this layout.
supply :REGULATOR_3V3, voltage: 3.3, plus: "T+1", minus: "T-1"
net :VCC, at: "T+1"
net :GND, at: "T-1"

part :PICO, :rp2040_clone, at: "c1", unused: (1..40).to_a - [1, 2, 3, 4, 5, 6, 35, 36, 38]
button :SWB, at: "e26", layer: "3 Switches"
button :SWA, at: "e30", layer: "3 Switches"
part :IR_RX, :ir_receiver, at: "c34", layer: ["4 IR", "5V emitter"]
part :IR_TX, :ir_emitter, at: "g34", layer: ["4 IR", "5V emitter"]

offboard :OLED, :ssd1306_oled, side: :right, at: "a7", address: "0x3C", layer: "2 I2C"
offboard :SHT31A, :sht31, side: :right, at: "a12", address: "0x44", unused: ["ALR"], layer: "2 I2C"
offboard :SHT31B, :sht31, side: :right, at: "a19", address: "0x45", unused: ["ALR"], layer: "2 I2C"

# Power: use the exposed holes sharing strips with the 3V3/GND pins, then bridge + rails.
wire "j5", "T+5", color: "#E24B4A", layer: "1 Power"
wire "j3", "T-3", color: "#888780", route: :edge, layer: "1 Power"
wire "a6", "B-6", color: "#888780", route: :edge, layer: "1 Power"
wire "T+38", "B+38", color: "#E24B4A", route: :arc, layer: "1 Power"

# I2C: the three modules share GP0/SDA and GP1/SCL.
wire "b1", "f24", color: "#378ADD", route: :edge, layer: "2 I2C"
wire "b2", "f22", color: "#EF9F27", route: :edge, layer: "2 I2C"
wire "OLED.GND", "T-7", color: "#888780", route: :edge, layer: "2 I2C"
wire "OLED.VCC", "T+8", color: "#E24B4A", route: :edge, layer: "2 I2C"
wire "OLED.SCL", "g22", color: "#EF9F27", route: :edge, layer: "2 I2C"
wire "OLED.SDA", "g24", color: "#378ADD", route: :edge, layer: "2 I2C"
wire "SHT31A.VIN", "T+12", color: "#E24B4A", route: :edge, layer: "2 I2C"
wire "SHT31A.GND", "T-13", color: "#888780", route: :edge, layer: "2 I2C"
wire "SHT31A.SCL", "h22", color: "#EF9F27", route: :edge, layer: "2 I2C"
wire "SHT31A.SDA", "h24", color: "#378ADD", route: :edge, layer: "2 I2C"
wire "SHT31A.ADR", "T-16", color: "#888780", route: :edge, layer: "2 I2C"
wire "SHT31B.VIN", "T+19", color: "#E24B4A", route: :edge, layer: "2 I2C"
wire "SHT31B.GND", "T-20", color: "#888780", route: :edge, layer: "2 I2C"
wire "SHT31B.SCL", "i22", color: "#EF9F27", route: :edge, layer: "2 I2C"
wire "SHT31B.SDA", "i24", color: "#378ADD", route: :edge, layer: "2 I2C"
wire "SHT31B.ADR", "T+23", color: "#E24B4A", route: :edge, layer: "2 I2C"

# Buttons: each GPIO is pulled to ground when its switch is pressed.
wire "b5", "a26", color: "#639922", route: :edge, layer: "3 Switches"
wire "j28", "T-28", color: "#888780", route: :edge, layer: "3 Switches"
wire "b4", "a30", color: "#639922", route: :edge, layer: "3 Switches"
wire "j32", "T-32", color: "#888780", route: :edge, layer: "3 Switches"

# IR receiver wiring remains visible in both IR views.
wire "b3", "a34", color: "#D4537E", route: :edge, layer: ["4 IR", "5V emitter"]
wire "a35", "B+35", color: "#E24B4A", route: :edge, layer: ["4 IR", "5V emitter"]
wire "a36", "B-36", color: "#888780", route: :edge, layer: ["4 IR", "5V emitter"]
wire "j34", "T+34", color: "#E24B4A", route: :edge, layer: "4 IR"
wire "j35", "T-35", color: "#888780", route: :edge, layer: ["4 IR", "5V emitter"]

# Select this view only after removing the emitter's 3.3 V rail wire above.
wire "j34", "j1", color: "#D85A30", route: :edge, layer: "5V emitter", electrical: false, dashed: true

expect do
  connected "PICO.GP0", "OLED.SDA", "SHT31A.SDA", "SHT31B.SDA"
  connected "PICO.GP1", "OLED.SCL", "SHT31A.SCL", "SHT31B.SCL"
  connected "PICO.GP2", "IR_RX.OUT"
  connected "PICO.GP3", "SWA.1"
  connected "SWA.3", :GND
  connected "PICO.GP4", "SWB.1"
  connected "SWB.3", :GND
  connected "PICO.3V3", "OLED.VCC", "SHT31A.VIN", "SHT31B.VIN", :VCC
  connected "PICO.GND", "PICO.GND2", "PICO.GND3", "OLED.GND", "SHT31A.GND", "SHT31B.GND", :GND
  connected "SHT31A.ADR", "SHT31A.GND"
  connected "SHT31B.ADR", "SHT31B.VIN"
  isolated "PICO.GP0", "PICO.GP1", "PICO.3V3", "PICO.GND"
end
