# frozen_string_literal: true

require "tmpdir"

RSpec.describe "offboard supply routing" do
  def resolve(source)
    builder = Breadkit::DSL::Builder.new
    builder.instance_eval(source, "source_supply.bk.rb", 1)
    Breadkit::Resolver.new.call(builder.document)
  end

  it "connects both provided pins to free rail holes without adding a voltage source" do
    circuit = resolve(<<~RUBY)
      board :half
      offboard :UNO, :arduino_uno
      supply from: "UNO.5V", plus: "T+", minus: "T-"
    RUBY

    expect(circuit.diagnostics).to be_empty
    expect(circuit.supplies).to be_empty
    expect(circuit.voltage_sources.map(&:name)).to contain_exactly("UNO.5V", "UNO.3V3")
    expect(circuit.wires.map(&:from)).to eq(%w[UNO.5V UNO.GND])
    expect(circuit.wires.map(&:to)).to match([/\AT\+\d+\z/, /\AT-\d+\z/])
    expect(circuit.net_of("UNO.5V")).to eq(circuit.net_of("T+1"))
    expect(circuit.net_of("UNO.GND")).to eq(circuit.net_of("T-1"))
    expect(circuit.potentials.values.fetch(circuit.net_of("T+1").name) - circuit.potentials.values.fetch(circuit.net_of("T-1").name)).to eq(5.0)
    expect(Breadkit::IR::Reader.new.read(circuit.to_ir).to_ir).to eq(circuit.to_ir)
  end

  it "selects the matching metadata entry for another provided output" do
    circuit = resolve('board :half; offboard :UNO, :arduino_uno; supply from: "UNO.3V3", plus: "B+", minus: "B-"')
    expect(circuit.diagnostics).to be_empty
    expect(circuit.wires.map(&:from)).to eq(%w[UNO.3V3 UNO.GND])
    expect(circuit.potentials.values.fetch(circuit.net_of("B+1").name) - circuit.potentials.values.fetch(circuit.net_of("B-1").name)).to eq(3.3)
  end

  it "preserves step metadata and chooses rails on a named board" do
    circuit = resolve(<<~RUBY)
      board :half, as: :B1
      offboard :UNO, :arduino_uno
      step 1 do
        supply from: "UNO.5V", plus: "B1.T+", minus: "B1.T-"
      end
    RUBY
    expect(circuit.diagnostics).to be_empty
    expect(circuit.wires.map(&:step)).to eq([1, 1])
    expect(circuit.wires.map(&:to)).to match([/\AB1\.T\+\d+\z/, /\AB1\.T-\d+\z/])
    expect(circuit.to_ir.fetch(:schema_version)).to eq(2)
    expect(Breadkit::IR::Reader.new.read(circuit.to_ir).to_ir).to eq(circuit.to_ir)
  end

  it "rejects unknown, non-output, and ambiguous source pins" do
    unknown = resolve('board :half; supply from: "UNO.5V", plus: "T+", minus: "T-"')
    expect(unknown.diagnostics.map(&:code)).to include("unknown_supply_source")
    gpio = resolve('board :half; offboard :UNO, :arduino_uno; supply from: "UNO.D13", plus: "T+", minus: "T-"')
    expect(gpio.diagnostics.map(&:code)).to include("unknown_supply_source")
    expect(gpio.wires).to be_empty

    builder = Breadkit::DSL::Builder.new
    uno = Breadkit::PartLibrary.new.find("arduino_uno")
    duplicate = Marshal.load(Marshal.dump(uno.data))
    duplicate["override"] = true
    duplicate["provides"] << { "positive" => "5V", "negative" => "GND2", "voltage" => 5 }
    builder.document.part_definitions << duplicate
    builder.instance_eval('board :half; offboard :UNO, :arduino_uno; supply from: "UNO.5V", plus: "T+", minus: "T-"', "source_supply.bk.rb", 1)
    ambiguous = Breadkit::Resolver.new.call(builder.document)
    expect(ambiguous.diagnostics.map(&:code)).to include("ambiguous_supply_source")
    expect(ambiguous.wires).to be_empty
  end

  it "requires a complete source route and rejects mixing standalone supply options" do
    builder = Breadkit::DSL::Builder.new
    expect { builder.instance_eval('supply from: "UNO.5V"', "source_supply.bk.rb", 1) }
      .to raise_error(Breadkit::DSLError, /plus and minus/)
    expect { builder.instance_eval('supply :BAT, from: "UNO.5V", plus: "T+", minus: "T-"', "source_supply.bk.rb", 1) }
      .to raise_error(Breadkit::DSLError, /cannot mix/)
  end

  it "keeps source declarations intact when the same document is resolved again" do
    builder = Breadkit::DSL::Builder.new
    builder.instance_eval('board :half; supply from: "MISSING.5V", plus: "T+", minus: "T-"', "source_supply.bk.rb", 1)
    results = 2.times.map { Breadkit::Resolver.new.call(builder.document) }
    expect(results.map { |result| result.diagnostics.map(&:code) }).to eq([%w[unknown_supply_source], %w[unknown_supply_source]])
  end

  it "accepts the same shorthand in declarative YAML and TOML" do
    Dir.mktmpdir do |dir|
      yaml = File.join(dir, "supply.bk.yml")
      toml = File.join(dir, "supply.bk.toml")
      File.write(yaml, <<~YAML)
        board: half
        offboard:
          - {ref: UNO, type: arduino_uno}
        supplies:
          - {from: UNO.5V, plus: T+, minus: T-}
      YAML
      File.write(toml, <<~TOML)
        board = "half"
        [[offboard]]
        ref = "UNO"
        type = "arduino_uno"
        [[supplies]]
        from = "UNO.5V"
        plus = "T+"
        minus = "T-"
      TOML
      [yaml, toml].each do |path|
        circuit = Breadkit.load(path)
        expect(circuit.diagnostics).to be_empty
        expect(circuit.wires.map(&:from)).to eq(%w[UNO.5V UNO.GND])
      end
    end
  end
end
