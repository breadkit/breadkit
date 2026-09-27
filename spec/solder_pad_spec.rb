# frozen_string_literal: true

RSpec.describe "soldered board wires" do
  def resolve(source)
    Breadkit::Resolver.new.call(Breadkit::DSL.load_file("solder.bk.rb", source: source))
  end

  it "attaches a wire to the occupied pad of a component pin on universal perfboard" do
    circuit = resolve('board :universal; resistor :R1, "330", pins: %w[a1 a2]; wire "R1.1", "b1"')

    expect(circuit.diagnostics).to be_empty
    expect(circuit.wires.first.from).to eq("a1")
    expect(circuit.net_of("R1.1")).to eq(circuit.net_of("b1"))
  end

  it "allows several wires to share a solder pad but still rejects overlapping component leads" do
    circuit = resolve('board :universal; resistor :R1, "330", pins: %w[a1 a2]; wire "R1.1", "b1"; wire "a1", "c1"')
    expect(circuit.diagnostics).to be_empty
    expect(circuit.wires.map(&:from)).to eq(%w[a1 a1])
    expect(circuit.net_of("c1")).to eq(circuit.net_of("R1.1"))

    overlap = resolve('board :universal; resistor :R1, "330", pins: %w[a1 a2]; resistor :R2, "330", pins: %w[a1 a3]')
    expect(overlap.diagnostics.map(&:code)).to include("hole_conflict")
  end

  it "uses a free stripboard hole when available and preserves breadboard occupancy" do
    stripboard = resolve('board :stripboard; resistor :R1, "330", pins: %w[a1 b1]; wire "R1.1", "c1"')
    expect(stripboard.diagnostics).to be_empty
    expect(stripboard.wires.first.from).to eq("a2")
    expect(stripboard.net_of("R1.1")).to eq(stripboard.net_of("c1"))

    breadboard = resolve('board :half; resistor :R1, "330", pins: %w[a1 a3]; wire "a1", "b3"')
    expect(breadboard.diagnostics.map(&:code)).to include("hole_conflict")
  end

  it "keeps solder-pad behavior on a named board through IR" do
    circuit = resolve('board :universal, as: :B1; board :mini, as: :B2; resistor :R1, "330", pins: %w[B1.a1 B1.a2]; wire "R1.1", "B2.a1"')
    expect(circuit.diagnostics).to be_empty
    expect(circuit.wires.first.from).to eq("B1.a1")
    restored = Breadkit::IR::Reader.new.read(circuit.to_ir)
    expect(restored.net_of("R1.1")).to eq(restored.net_of("B2.a1"))
  end
end
