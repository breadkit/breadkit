# expect: Electrical/ShortCircuit
board :half
supply :USB, voltage: 5.0, plus: "B+1", minus: "B-1"
wire "a10", "B+"
wire "b10", "B-"
