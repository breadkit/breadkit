# frozen_string_literal: true

require "json_schemer"

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
    let(:path) { File.expand_path("../../examples/01_led_button.bk.rb", __dir__) }
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

    it "round-trips every example through schema-valid IR" do
      schema = JSON.parse(File.read(File.expand_path("../schema/ir-v1.json", __dir__)))
      schemer = JSONSchemer.schema(schema)
      examples = Dir[File.expand_path("../../examples/*.bk.rb", __dir__)].sort

      examples.each do |path|
        ir = Breadkit.load(path).to_ir
        expect(schemer.validate(ir).to_a).to be_empty, "#{File.basename(path)} does not match schema"
        expect(Breadkit::IR::Reader.new.read(ir).to_ir).to eq(ir)
      end
      expect(schemer.valid?({ "schema_version" => 1 })).to be(false)
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

  it "reports unknown expectation references and finds a short-circuit path" do
    builder = Breadkit::DSL::Builder.new
    builder.instance_eval('board :half; resistor :R1, "330", pins: %w[a1 a3]; expect { connected "R1.3", :MISSING }', "bad.bk.rb", 1)
    circuit = Breadkit::Resolver.new.call(builder.document)
    expect(circuit.diagnostics.map(&:code)).to include("unknown_pin", "unknown_net")

    short = Breadkit.load(File.expand_path("../../examples/bad/short_circuit.bk.rb", __dir__))
    path = short.shortest_path("USB.+", "USB.-")
    expect(path).to include("W1", "W2")
    expect(path.length).to be < 10
  end

  it "resolves generic DIP pins and wires to offboard module pins" do
    builder = Breadkit::DSL::Builder.new
    builder.instance_eval('board :half; part :U1, :dip, pin_count: 8, at: "e20"; offboard :UNO, "arduino_uno"; wire "UNO.D13", "a1"', "sample.bk.rb", 1)
    circuit = Breadkit::Resolver.new.call(builder.document)

    expect(circuit.diagnostics).to be_empty
    expect(circuit.components.fetch("U1").pins.size).to eq(8)
    expect(circuit.nets.find { |net| net.members.include?("UNO.D13") }.members).to include("W1")
  end

  it "allocates a free strip hole for a wire that names a component pin" do
    builder = Breadkit::DSL::Builder.new
    builder.instance_eval('board :half; ic :U1, "NE555", at: "e20"; wire "U1.8", "B+"', "sample.bk.rb", 1)
    circuit = Breadkit::Resolver.new.call(builder.document)
    wire = circuit.wires.first
    pin = circuit.components.fetch("U1").pins.fetch("VCC")

    expect(circuit.diagnostics).to be_empty
    expect(circuit.board.strip(wire.from)).to include(pin.hole_id)
    expect(wire.from).not_to eq(pin.hole_id)
  end

  it "lists and creates configurable generic DIP and pin-header definitions" do
    library = Breadkit::PartLibrary.new
    expect(library.all.map(&:id)).to include("dip", "pin_header")
    expect(library.find("dip", pin_count: 14).pins.length).to eq(14)
    expect(library.find("pin_header", pin_count: 6).pins.length).to eq(6)
    expect(library.find("dip", pin_count: 100)).to be_nil
  end

  it "emits each resolver diagnostic required by the lint bridge" do
    declarations = {
      invalid_hole: 'resistor :R1, "330", pins: %w[k5 a2]',
      unknown_part: 'part :X1, :missing_part, pins: %w[a1 a3]',
      unknown_pin: 'ic :U1, "NE555", at: "e20"; wire "U1.9", "a10"',
      duplicate_ref: 'resistor :R1, "330", pins: %w[a1 a3]; resistor :R1, "1k", pins: %w[a5 a7]',
      invalid_placement: 'ic :U1, "NE555", at: "c20"',
      hole_conflict: 'resistor :R1, "330", pins: %w[a1 a3]; resistor :R2, "220", pins: %w[a1 a6]',
      no_free_hole: 'part :J1, :pin_header, pin_count: 5, pins: %w[a1 b1 c1 d1 e1]; wire "J1.1", "a10"',
      unknown_net: 'expect { connected :MISSING, "a1" }'
    }
    declarations.each do |expected, source|
      builder = Breadkit::DSL::Builder.new
      builder.instance_eval("board :half; #{source}", "diagnostic.bk.rb", 1)
      codes = Breadkit::Resolver.new.call(builder.document).diagnostics.map(&:code)
      expect(codes).to include(expected.to_s), "expected #{expected} from #{source}"
    end
  end

  describe Breadkit::CLI do
    let(:example) { File.expand_path("../../examples/01_led_button.bk.rb", __dir__) }

    it "prints nets, switch states, IR, and part definitions" do
      status = nil
      expect { status = described_class.new.run(["nets", example]) }.to output(/VCC:/).to_stdout
      expect(status).to eq(0)
      expect { status = described_class.new.run(["nets", example, "--state", "SW1"]) }.to output(/VCC:/).to_stdout
      expect(status).to eq(0)
      expect { status = described_class.new.run(["ir", example]) }.to output(/"schema_version": 1/).to_stdout
      expect(status).to eq(0)
      expect { status = described_class.new.run(["parts"]) }.to output(/pin_header/).to_stdout
      expect(status).to eq(0)
    end

    it "returns usage and input errors with non-success statuses" do
      cli = described_class.new
      status = nil
      expect { status = cli.run(["nets"]) }.to output(/usage: breadkit nets FILE/).to_stderr
      expect(status).to eq(2)
      expect { status = cli.run(["nets", example, "--state", "missing"]) }
        .to output(/unknown switch state missing/).to_stderr
      expect(status).to eq(2)
      expect { status = cli.run(["unknown"]) }.to output(/Usage: breadkit/).to_stdout
      expect(status).to eq(2)
      expect { status = cli.run(["--help"]) }.to output(/Usage: breadkit/).to_stdout
      expect(status).to eq(0)
    end
  end
end
