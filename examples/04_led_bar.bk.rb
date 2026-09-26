# frozen_string_literal: true

title "Four LED bar"
board :half
supply :USB, voltage: 5.0, plus: "B+1", minus: "B-1"
net :VCC, at: "B+1"
net :GND, at: "B-1"

4.times do |index|
  column = 5 + index * 4
  resistor :"R#{index + 1}", "220", pins: ["a#{column}", "a#{column + 1}"]
  led :"D#{index + 1}", color: :green, anode: "b#{column + 1}", cathode: "b#{column + 2}"
  wire "c#{column}", "B+", color: :red
  wire "c#{column + 2}", "B-", color: :black
end
