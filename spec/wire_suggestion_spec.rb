# frozen_string_literal: true

require "stringio"

RSpec.describe "wire suggestions for connection intent" do
  def circuit(source)
    Breadkit::Resolver.new.call(Breadkit::DSL.load_file("suggest.bk.rb", source: source))
  end

  it "chooses explicit free holes for two placed pins and preserves the result through IR" do
    source = 'connect "R1.1", "R2.1"; board :mini; resistor :R1, "330", pins: %w[a1 a2]; resistor :R2, "1k", pins: %w[a4 a5]'
    resolved = circuit(source)
    expected = [{ from: "b1", to: "b4", refs: %w[R1.1 R2.1] }]
    expect(resolved.wire_suggestions).to eq(expected)
    expect(resolved.wires).to be_empty
    expect(Breadkit::IR::Reader.new.read(resolved.to_ir).wire_suggestions).to eq(expected)
    expect(circuit(source + '; wire "b1", "b4"').wire_suggestions).to be_empty
  end

  it "skips offboard pins, switch-state intent, and strips without two free endpoints" do
    offboard = circuit('board :mini; offboard :UNO, :arduino_uno; resistor :R1, "330", pins: %w[a1 a2]; connect "UNO.D13", "R1.1"')
    expect(offboard.wire_suggestions).to be_empty

    state = circuit('board :mini; resistor :R1, "330", pins: %w[a1 a2]; resistor :R2, "1k", pins: %w[a4 a5]; connect "R1.1", "R2.1", when: "SW1"')
    expect(state.wire_suggestions).to be_empty

    occupied = circuit('board :mini; part :J1, :pin_header, pin_count: 5, pins: %w[a1 b1 c1 d1 e1]; resistor :R1, "330", pins: %w[a4 a5]; connect "J1.1", "R1.1"')
    expect(occupied.wire_suggestions).to be_empty
  end

  it "uses qualified holes across named boards and skips invalid placements" do
    named = circuit('board :mini, as: :B1; board :mini, as: :B2; resistor :R1, "330", pins: %w[B1.a1 B1.a2]; resistor :R2, "1k", pins: %w[B2.a1 B2.a2]; connect "R1.1", "R2.1"')
    expect(named.wire_suggestions).to eq([{ from: "B1.b1", to: "B2.b1", refs: %w[R1.1 R2.1] }])

    invalid = circuit('board :mini; resistor :R1, "330", pins: %w[a1 z99]; resistor :R2, "1k", pins: %w[a4 a5]; connect "R1.1", "R2.1"')
    expect(invalid.wire_suggestions).to be_empty
  end

  it "does not reserve the same free hole for two suggestions" do
    source = 'board :mini; connect "R1.1", "R2.1"; connect "R1.1", "R3.1"; resistor :R1, "330", pins: %w[a1 a2]; resistor :R2, "1k", pins: %w[a4 a5]; resistor :R3, "1k", pins: %w[a8 a9]'
    suggestions = circuit(source).wire_suggestions
    expect(suggestions.length).to eq(2)
    expect(suggestions.flat_map { |item| item.values_at(:from, :to) }.uniq.length).to eq(4)
  end

  it "does not repeat a suggestion for duplicate connection intent" do
    source = 'board :mini; connect "R1.1", "R2.1"; connect "R2.1", "R1.1"; resistor :R1, "330", pins: %w[a1 a2]; resistor :R2, "1k", pins: %w[a4 a5]'
    expect(circuit(source).wire_suggestions.length).to eq(1)

    transitive = 'board :mini; connect "R1.1", "R2.1"; connect "R2.1", "R3.1"; connect "R1.1", "R3.1"; resistor :R1, "330", pins: %w[a1 a2]; resistor :R2, "1k", pins: %w[a4 a5]; resistor :R3, "1k", pins: %w[a8 a9]'
    expect(circuit(transitive).wire_suggestions.length).to eq(2)
  end

  it "does not place a suggested jumper under a module body" do
    builder = Breadkit::DSL::Builder.new
    builder.document.part_definitions << { "id" => "cover", "placement" => "footprint",
      "pins" => [{ "num" => 1 }, { "num" => 2 }], "footprint" => { "1" => [0, 0], "2" => [1, 0] },
      "render" => { "shape" => "module", "size_mm" => [10, 10] } }
    builder.instance_eval('board :mini; part :U1, :cover, at: "c1"; resistor :R1, "330", pins: %w[a1 a2]; resistor :R2, "1k", pins: %w[a4 a5]; connect "R1.1", "R2.1"', "suggest.bk.rb", 1)
    suggestions = Breadkit::Resolver.new.call(builder.document).wire_suggestions
    expect(suggestions).to eq([{ from: "e1", to: "e4", refs: %w[R1.1 R2.1] }])
  end

  it "does not suggest a wire between nets with conflicting known voltages" do
    source = 'board :half; supply :USB, voltage: 5, plus: "B+1", minus: "B-1"; resistor :R1, "330", pins: %w[a1 a2]; resistor :R2, "1k", pins: %w[a4 a5]; wire "B+3", "b1"; wire "B-3", "b4"; connect "R1.1", "R2.1"'
    expect(circuit(source).wire_suggestions).to be_empty
  end

  it "does not suggest a wire when the existing circuit already has a power conflict" do
    source = 'board :half; supply :USB, voltage: 5, plus: "B+1", minus: "B-1"; wire "B+3", "B-3"; resistor :R1, "330", pins: %w[a1 a2]; resistor :R2, "1k", pins: %w[a4 a5]; connect "R1.1", "R2.1"'
    resolved = circuit(source)
    expect(resolved.potentials.conflicts).not_to be_empty
    expect(resolved.wire_suggestions).to be_empty
  end

  it "does not combine candidates that would jointly bridge different known voltages" do
    source = 'board :half; supply :USB, voltage: 5, plus: "B+1", minus: "B-1"; resistor :R1, "330", pins: %w[a1 a2]; resistor :R2, "1k", pins: %w[a4 a5]; resistor :R3, "1k", pins: %w[a8 a9]; wire "B+3", "b1"; wire "B-3", "b8"; connect "R1.1", "R2.1"; connect "R2.1", "R3.1"'
    expect(circuit(source).wire_suggestions.map { |item| item[:refs] }).to eq([%w[R1.1 R2.1]])
  end

  it "prints machine-readable candidates without changing the circuit" do
    require "tmpdir"
    Dir.mktmpdir do |dir|
      path = File.join(dir, "suggest.bk.rb")
      File.write(path, 'connect "R1.1", "R2.1"; board :mini; resistor :R1, "330", pins: %w[a1 a2]; resistor :R2, "1k", pins: %w[a4 a5]')
      output = StringIO.new
      original = $stdout
      $stdout = output
      expect(Breadkit::CLI.new.run(["suggest", path])).to eq(0)
      expect(JSON.parse(output.string)).to eq([{ "from" => "b1", "to" => "b4", "refs" => %w[R1.1 R2.1] }])
    ensure
      $stdout = original
    end
  end
end
