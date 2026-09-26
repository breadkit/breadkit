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

    it "round-trips every example through schema-valid IR" do
      schema = JSON.parse(File.read(File.expand_path("../schema/ir-v1.json", __dir__)))
      schemer = JSONSchemer.schema(schema)
      examples = Dir[File.expand_path("../examples/*.bk.rb", __dir__)].sort

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

    short = Breadkit.load(File.expand_path("../examples/bad/short_circuit.bk.rb", __dir__))
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

  it "requires physical dimensions for a generic module rendering" do
    definition = { "id" => "display", "pins" => [], "render" => { "shape" => "module", "size_mm" => [27, 0] } }

    expect { Breadkit::PartDef.new(definition) }.to raise_error(ArgumentError, /positive size_mm/)
  end

  it "rejects non-finite generic module body offsets" do
    definition = { "id" => "display", "pins" => [],
                   "render" => { "shape" => "module", "size_mm" => [27, 20], "body_offset_mm" => [0, Float::INFINITY] } }

    expect { Breadkit::PartDef.new(definition) }.to raise_error(ArgumentError, /body_offset_mm/)
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
    let(:example) { File.expand_path("../examples/01_led_button.bk.rb", __dir__) }

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
      expect { status = cli.run(["unknown"]) }.to output(/Usage: breadkit/).to_stderr
      expect(status).to eq(2)
      expect { status = cli.run(["--help"]) }.to output(/Usage: breadkit/).to_stdout
      expect(status).to eq(0)
    end
  end
end

RSpec.describe "resolver and DSL regressions" do
  def resolve(source)
    builder = Breadkit::DSL::Builder.new
    builder.instance_eval(source, "review.bk.rb", 1)
    Breadkit::Resolver.new.call(builder.document)
  end

  it "reports occupied holes with a valid severity and location" do
    circuit = resolve('board :half; resistor :R1, "330", pins: %w[a1 a3]; resistor :R2, "330", pins: %w[a1 a5]')
    conflict = circuit.diagnostics.find { |item| item.code == "hole_conflict" }
    expect([conflict.severity, conflict.location.path, conflict.targets]).to eq(["error", "review.bk.rb", ["R2", "a1"]])
  end

  it "reverses both sides of a DIP anchored on f" do
    pins = resolve('board :half; ic :U1, "NE555", at: "f20"').components.fetch("U1").pins
    expect(pins.transform_values(&:hole_id).values_at("GND", "RESET", "CTRL", "VCC")).to eq(%w[f20 f17 e17 e20])
  end

  it "reads UTF-8 DSL files independently of the external encoding" do
    require "tempfile"
    Tempfile.create(["breadkit", ".bk.rb"]) do |file|
      file.write("title '発酵'; board :half\n")
      file.flush
      original_encoding = Encoding.default_external
      begin
        Encoding.default_external = Encoding::US_ASCII
        expect(Breadkit.load(file.path).title).to eq("発酵")
      ensure
        Encoding.default_external = original_encoding
      end
    end
  end

  it "resolves case-insensitive pin names and aliases in wires and expectations" do
    circuit = resolve('board :half; led :D1, anode: "a1", cathode: "a2"; wire "D1.A", "a5"; expect { connected "D1.+", "a5" }')
    expect(circuit.diagnostics).to be_empty
    expect(circuit.net_of("D1.A")).to eq(circuit.net_of("D1.+"))
    placed = resolve('board :half; led :D2, pins: { "ANODE" => "a1", "CATHODE" => "a2" }')
    expect(placed.components.fetch("D2").pins.values.map(&:hole_id)).to eq(%w[a1 a2])
    expect(placed.diagnostics).to be_empty
  end

  it "reports unknown and missing placement pins" do
    circuit = resolve('board :half; led :D1, anode: "a1", cathod: "a2"')
    expect(circuit.diagnostics.map(&:code)).to include("unknown_pin", "unplaced_pin")
    expect(resolve('board :half; resistor :R1, "330", pins: ["a1"]').diagnostics.map(&:code)).to include("unplaced_pin")
  end

  it "places header footprints and rejects at for lead-only parts" do
    header = resolve('board :half; part :J1, :pin_header, pin_count: 4, at: "a1"')
    expect(header.components.fetch("J1").pins.values.map(&:hole_id)).to eq(%w[a1 a2 a3 a4])
    expect(header.diagnostics).to be_empty
    expect(resolve('board :half; resistor :R1, "330", at: "a1"').diagnostics.map(&:code)).to include("invalid_placement")
  end

  it "uses physical footprint offsets and requires a switch to cross the gap" do
    switch = resolve('board :half; button :SW1, at: "e10"')
    expect(switch.components.fetch("SW1").pins.values.map(&:hole_id)).to eq(%w[e10 f10 e12 f12])
    expect(switch.diagnostics).to be_empty
    expect(resolve('board :half; button :SW1, at: "a10"').diagnostics.map(&:code)).to include("invalid_placement")
    expect(resolve('board :half; button :SW1, pins: %w[a10 b10 a12 b12]').diagnostics.map(&:code)).to include("invalid_placement")
    expect(resolve('board :half; button :SW1, pins: %w[a10 f10 a12 f12]').diagnostics.map(&:code)).to include("invalid_placement")
    expect(resolve('board :half; button :SW1, pins: %w[e10 f10 e12 f12]').diagnostics).to be_empty
  end

  it "places every example footprint on its physical pin rows" do
    sensor = Breadkit.load(File.expand_path("../examples/05_sensor_demo.bk.rb", __dir__))
    pico = sensor.components.fetch("PICO")
    expect(sensor.diagnostics).to be_empty
    expect(pico.pins.values_at("GP0", "GP1", "GND3", "3V3", "GND2", "VIN", "VBUS").map(&:hole_id))
      .to eq(%w[c1 c2 h6 h5 h3 h2 h1])
    expect(sensor.components.fetch("IR_RX").pins.values.map(&:hole_id)).to eq(%w[c34 c35 c36])
    expect(sensor.components.fetch("IR_TX").pins.values.map(&:hole_id)).to eq(%w[g34 g35])

    builder = Breadkit::DSL::Builder.new(base_dir: File.expand_path("..", __dir__))
    builder.instance_eval('use_parts "examples/parts/pico_w.yml"; board :full; part :PICO, :pico_w, at: "c1"', "review.bk.rb", 1)
    pico_w = Breadkit::Resolver.new.call(builder.document)
    expect(pico_w.diagnostics).to be_empty
    expect(pico_w.components.fetch("PICO").pins.fetch("VBUS").hole_id).to eq("h1")
    expect(resolve('board :half; pot :VR1, "10k", at: "a1"').components.fetch("VR1").pins.values.map(&:hole_id)).to eq(%w[a1 a2 a3])
  end

  it "reports a footprint outside the board once" do
    circuit = resolve('board :half; button :SW1, at: "e30"')
    expect(circuit.diagnostics.count { |item| item.code == "invalid_placement" }).to eq(1)
  end

  it "reports an unknown wire pin once at the declaration" do
    circuit = resolve('board :half; resistor :R1, "330", pins: %w[a1 a3]; wire "R1.9", "a5"')
    unknown = circuit.diagnostics.select { |item| item.code == "unknown_pin" }
    expect(unknown.length).to eq(1)
    expect(unknown.first.location.line).to eq(1)
    expect(circuit.diagnostics.map(&:code)).not_to include("no_free_hole")
  end

  it "reports unknown boards without treating them as unknown parts" do
    expect(resolve('board :missing').diagnostics.map(&:code)).to include("unknown_board")
  end

  it "skips explicitly reserved wire IDs and checks all declaration names" do
    circuit = resolve('board :half; resistor :R1, "330", pins: %w[a1 a3]; wire "a5", "a6"; wire "a7", "a8", id: "W2"; wire "a9", "a10"')
    expect(circuit.wires.map(&:id)).to eq(%w[W1 W2 W3])
    expect(circuit.diagnostics).to be_empty
    expect(resolve('board :half; supply :USB, voltage: "5V", plus: "B+1", minus: "B-1"; supply :USB, voltage: "5V", plus: "B+2", minus: "B-2"').diagnostics.map(&:code)).to include("duplicate_ref")
    expect(resolve('board :half; resistor :R1, "330", pins: %w[a1 a3]; wire "a5", "a6", id: "R1"').diagnostics.map(&:code)).to include("duplicate_ref")
  end

  it "parses common value notations and preserves units when formatting" do
    { "220R" => 220, "R47" => 0.47, "4n7" => 4.7e-9, "2u2" => 2.2e-6, "10µF" => 10e-6, "4.7kOhm" => 4700 }.each do |source, expected|
      expect(Breadkit::Value.parse(source)).to be_within(expected.abs * 1e-9).of(expected)
    end
    expect(Breadkit::Value.new("100nF").to_s).to eq("100nF")
    expect(Breadkit::Value.new("999.9").to_s).to eq("1kΩ")
    expect(Breadkit::Value.new("1p").to_s).to eq("1pΩ")
  end

  it "keeps Ruby reflection honest and wraps ScriptError with the DSL location" do
    expect(Breadkit::DSL::Builder.new.respond_to?(:to_ary)).to be(false)
    require "tempfile"
    Tempfile.create(["breadkit", ".bk.rb"]) do |file|
      file.write("require 'missing_breadkit_test_library'\n")
      file.flush
      expect { Breadkit::DSL.load_file(file.path) }.to raise_error(Breadkit::DSLError, /#{Regexp.escape(file.path)}:1:/)
    end
  end

  it "rejects misplaced expectations, positional labels, and duplicate boards" do
    builder = Breadkit::DSL::Builder.new
    expect { builder.connected("a1", "a2") }.to raise_error(Breadkit::DSLError)
    expect { builder.isolated("a1", "a2") }.to raise_error(Breadkit::DSLError)
    expect { builder.net(:VCC, "a1") }.to raise_error(Breadkit::DSLError)
    builder.board(:half)
    expect { builder.board(:full) }.to raise_error(Breadkit::DSLError)
  end

  it "reports disconnected nets with the same label" do
    circuit = resolve('board :half; net :VCC, at: "a1"; net :VCC, at: "a2"')
    expect(circuit.diagnostics.count { |item| item.code == "split_net_label" }).to eq(1)
    expect(circuit.nets.map(&:name)).to include("VCC")
  end

  it "grounds labeled GND and reports each conflicting supply once with its terminals" do
    circuit = resolve('board :half; supply :A, voltage: "5V", plus: "a1", minus: "a2"; supply :B, voltage: "3.3V", plus: "b1", minus: "b2"; net :GND, at: "c2"')
    result = circuit.potentials
    expect(result.values["GND"]).to eq(0.0)
    expect(result.conflicts.length).to eq(1)
    expect([result.conflicts.first[:terminal_a], result.conflicts.first[:terminal_b]]).to contain_exactly("A.+", "B.+")
    expect(result.conflicts.first[:location]).not_to be_nil
    bipolar = resolve('board :half; supply :POS, voltage: "5V", plus: "a1", minus: "a2"; supply :NEG, voltage: "5V", plus: "b2", minus: "b3"; net :GND, at: "c2"; wire "a1", "a3"')
    conflict = bipolar.potentials.conflicts.fetch(0)
    expect([conflict[:terminal_a], conflict[:terminal_b]]).to contain_exactly("POS.+", "NEG.-")
    expect(conflict[:wires]).to eq(["W1"])
    switched = resolve('board :half; button :SW1, at: "e10"; net :VCC, at: "a12"; net :GND, at: "a10"; supply :USB, voltage: "5V", plus: "b12", minus: "a1"')
    closed = switched.states.last
    expect(switched.potentials(closed).values["VCC"]).to eq(0.0)
    expect(switched.potentials(closed).values["USB-"]).to eq(-5.0)
  end

  it "indexes net references once per state" do
    circuit = resolve('board :half; resistor :R1, "330", pins: %w[a1 a3]')
    expect(Breadkit::Connectivity).to receive(:new).once.and_call_original
    5.times do
      expect(circuit.net_of("R1.1").members).to include("R1.1")
      expect(circuit.net_of("R1.2").members).to include("R1.2")
    end
  end

  it "closes all poles of a switch in one physical state" do
    builder = Breadkit::DSL::Builder.new
    builder.document.part_definitions << { "id" => "dpst", "placement" => "offboard",
                                           "pins" => (1..4).map { |number| { "num" => number } },
                                           "switch" => [[1, 2], [3, 4]] }
    builder.instance_eval('board :half; offboard :SW1, :dpst', "review.bk.rb", 1)
    circuit = Breadkit::Resolver.new.call(builder.document)
    expect(circuit.states("single").map(&:name)).to eq([nil, "SW1"])
    expect(circuit.states("single").last.closed_switches.length).to eq(2)
    expect(circuit.states("all").map(&:name)).to eq([nil, "SW1"])
  end

  it "finds paths through offboard pins without board holes" do
    circuit = resolve('board :half; offboard :UNO, :arduino_uno; wire "UNO.D13", "a1"; wire "UNO.D13", "a2"')
    expect(circuit.shortest_path("a1", "a2")).to include("W1", "UNO.D13", "W2")
  end

  it "round-trips custom boards and lint disables with relative source paths" do
    require "tempfile"
    Tempfile.create(["breadkit-board", ".yml"]) do |board|
      board.write("id: custom_review\nterminal:\n  columns: 2\n  rows: [a, b]\n  groups: [[a, b]]\n")
      board.flush
      Tempfile.create(["breadkit-circuit", ".bk.rb"]) do |dsl|
        dsl.write("use_boards #{board.path.inspect}\nboard :custom_review\nnet :GND, at: 'a1'\nlint_disable 'Style/WireColor', reason: 'example'\n")
        dsl.flush
        ir = Breadkit.load(dsl.path).to_ir
        expect(ir.dig(:board_definition, "id")).to eq("custom_review")
        expect(ir.fetch(:lint_disables).first.fetch("rule")).to eq("Style/WireColor")
        expect(ir.dig(:labels, 0, :source, :path)).not_to start_with("/")
        expect(ir.dig(:lint_disables, 0, "location", "path")).not_to start_with("/")
        expect(Breadkit::IR::Reader.new.read(ir).to_ir).to eq(ir)
      end
    end
  end

  it "rejects malformed IR types and accepts omitted analysis" do
    reader = Breadkit::IR::Reader.new
    ir = Breadkit.load(File.expand_path("../examples/01_led_button.bk.rb", __dir__)).to_ir
    ir.delete(:analysis)
    expect(reader.read(ir).board.definition.id).to eq("half")
    ir[:components] = "invalid"
    expect { reader.read(ir) }.to raise_error(Breadkit::DSLError, /components must be an array/)
    ir[:components] = []
    ir[:board_definition]["terminal"] = "invalid"
    expect { reader.read(ir) }.to raise_error(Breadkit::DSLError, /board_definition.terminal must be an object/)
  end

  it "parses CLI options before the file and lists custom parts" do
    cli = Breadkit::CLI.new
    example = File.expand_path("../examples/01_led_button.bk.rb", __dir__)
    sensor = File.expand_path("../examples/05_sensor_demo.bk.rb", __dir__)
    status = nil
    expect { status = cli.run(["nets", "--state", "SW1", example]) }.to output(/VCC:/).to_stdout
    expect(status).to eq(0)
    expect { status = cli.run(["--version"]) }.to output(/#{Breadkit::VERSION}/).to_stdout
    expect(status).to eq(0)
    expect { status = cli.run(["parts", sensor]) }.to output(/rp2040_clone/).to_stdout
    expect(status).to eq(0)
    require "tempfile"
    Tempfile.create(["breadkit-conflict", ".bk.rb"]) do |file|
      file.write("board :half\nresistor :R1, '330', pins: %w[a1 a3]\nresistor :R2, '330', pins: %w[a1 a5]\n")
      file.flush
      expect { status = cli.run(["ir", file.path]) }.to output(/hole_conflict/).to_stderr
      expect(status).to eq(1)
    end
  end
end
