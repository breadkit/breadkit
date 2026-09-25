# expect: Electrical/FloatingPin
board :half
supply :USB, voltage: 5.0, plus: "B+1", minus: "B-1"
wire "a10", "B+"
led :D1, color: :red, anode: "b10", cathode: "b17"
