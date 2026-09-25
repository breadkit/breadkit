# frozen_string_literal: true

RSpec.describe Breadkit do
  describe Breadkit::Value do
    it "parses engineering suffixes and RKM values" do
      expect(described_class.parse("4.7k")).to eq(4700.0)
      expect(described_class.parse("4k7")).to eq(4700.0)
      expect(described_class.parse("10uF")).to be_within(1e-12).of(10e-6)
      expect(described_class.new("4.7k").to_s).to eq("4.7kΩ")
      expect { described_class.parse("k") }.to raise_error(ArgumentError)
    end
  end

  describe Breadkit::HoleId do
    it "normalizes board holes and keeps rail and pin references" do
      expect(described_class.parse("A10").to_s).to eq("a10")
      expect(described_class.parse("T+5").to_s).to eq("T+5")
      expect(described_class.parse("B+").index).to be_nil
      expect(described_class.parse("U1.3").kind).to eq(:pin)
      expect { described_class.parse("T*3") }.to raise_error(ArgumentError)
    end
  end

  describe Breadkit::Board do
    it "generates the built-in board sizes and split rails" do
      expect(described_class.new(Breadkit::BoardDef.load("full")).holes.size).to eq(830)
      half = described_class.new(Breadkit::BoardDef.load("half"))
      expect(half.holes.size).to eq(400)
      expect(half.hole("B+8").x).to eq(9.0)
      expect(half.hole("B-14").x).to eq(16.0)
      expect(described_class.new(Breadkit::BoardDef.load("mini")).holes.size).to eq(170)
      split = described_class.new(Breadkit::BoardDef.load("full"), split_rails: true)
      expect(split.hole("T+25").strip_id).not_to eq(split.hole("T+26").strip_id)
    end
  end

  describe "DSL and analysis" do
    let(:path) { File.expand_path("../examples/01_led_button.bk.rb", __dir__) }
    let(:circuit) { Breadkit.load(path) }

    it "resolves the example and assigns automatic rail holes deterministically" do
      expect(circuit.diagnostics).to be_empty
      expect(circuit.wires.map(&:to)).to eq(["B+8", "B-14"])
      expect(circuit.nets.map(&:name)).to eq(%w[VCC GND N1 N2])
      expect(circuit.net_of("SW1.1").name).to eq("VCC")
      expect(circuit.net_of("R1.2").name).to eq("N2")
      expect(circuit.states.map(&:name)).to eq([nil, "SW1"])
      expect(circuit.net_of("SW1.3", circuit.states.last).name).to eq("VCC")
    end

    it "round-trips resolved circuits through IR" do
      loaded = Breadkit::IR::Reader.new.read(circuit.to_ir)
      expect(loaded.to_ir).to eq(circuit.to_ir)
    end
  end

  it "assigns DIP pins on either side of the ravine" do
    builder = Breadkit::DSL::Builder.new
    builder.instance_eval('board :half; ic :U1, "NE555", at: "e20"', "sample.bk.rb", 1)
    forward = Breadkit::Resolver.new.call(builder.document)
    expect(forward.components.fetch("U1").pins.transform_values(&:hole_id).values_at("GND", "VCC")).to eq(%w[e20 f20])

    reverse_builder = Breadkit::DSL::Builder.new
    reverse_builder.instance_eval('board :half; ic :U1, "NE555", at: "f23"', "sample.bk.rb", 1)
    reverse = Breadkit::Resolver.new.call(reverse_builder.document)
    expect(reverse.components.fetch("U1").pins.transform_values(&:hole_id).values_at("GND", "VCC")).to eq(%w[f23 e23])
  end

  it "suggests DSL method names" do
    expect { Breadkit::DSL::Builder.new.instance_eval("registor :R1", "sample.bk.rb", 1) }
      .to raise_error(Breadkit::DSLError, /resistor/)
  end
end
