# frozen_string_literal: true

require "json_schemer"

RSpec.describe "review batch 3" do
  def custom_board
    { "id" => "custom_grid", "terminal" => { "columns" => 4, "rows" => %w[u v],
      "groups" => [%w[u], %w[v]], "ravine_between" => %w[u v] },
      "rails" => [{ "id" => "PWR", "side" => "top", "order" => 0, "polarity" => "+" },
                  { "id" => "RET", "side" => "top", "order" => 1, "polarity" => "-" }],
      "rail_layout" => { "segments" => [[1, 4]], "start_column" => 1 } }
  end

  it "names unlabelled supply nets without the pin separator" do
    builder = Breadkit::DSL::Builder.new
    builder.instance_eval('board :mini; supply :USB, voltage: 5, plus: "a1", minus: "a2"', "sample.bk.rb", 1)
    circuit = Breadkit::Resolver.new.call(builder.document)
    expect(circuit.net_of("USB.+").name).to eq("USB+")
    expect(circuit.net_of("USB.-").name).to eq("USB-")
  end

  it "resolves custom rows and rails through wires, nets and potentials" do
    builder = Breadkit::DSL::Builder.new
    builder.document.board_definitions << custom_board
    builder.instance_eval('board :custom_grid; supply :USB, voltage: 3.3, plus: "PWR1", minus: "RET1"; wire "u1", "PWR"; wire "v1", "RET"', "sample.bk.rb", 1)
    circuit = Breadkit::Resolver.new.call(builder.document)
    expect(circuit.diagnostics).to be_empty
    expect(circuit.board.rail_polarity("PWR")).to eq("+")
    expect(circuit.board.rail_polarity("RET")).to eq("-")
    expect(circuit.net_of("u1")).to eq(circuit.net_of("PWR1"))
    expect(circuit.net_of("v1")).to eq(circuit.net_of("RET1"))
    expect(circuit.net_of("PWR1").potential).to eq(3.3)
    expect(circuit.wires.map(&:to)).to all(match(/\A(?:PWR|RET)\d+\z/))
    expect(Breadkit::IR::Reader.new.read(circuit.to_ir).net_of("u1")).not_to be_nil
  end

  it "rejects documented component options that have no implementation" do
    builder = Breadkit::DSL::Builder.new
    expect { builder.instance_eval('resistor :R1, "1k", pins: %w[a1 a2], rotate: 90', "sample.bk.rb", 1) }
      .to raise_error(Breadkit::DSLError, /rotate/)
    expect { builder.instance_eval('offboard :UNO, "arduino_uno", wire_layer: :below', "sample.bk.rb", 1) }
      .to raise_error(Breadkit::DSLError, /wire_layer/)
  end

  it "rejects ambiguous board row and rail names" do
    invalid = custom_board
    invalid["rails"] << { "id" => "U", "side" => "top", "order" => 2 }
    expect { Breadkit::BoardDef.new(invalid) }.to raise_error(ArgumentError, /row.*rail/i)
    duplicate = custom_board
    duplicate["terminal"]["rows"] = %w[u U]
    expect { Breadkit::BoardDef.new(duplicate) }.to raise_error(ArgumentError, /duplicate row/i)
    numbered = custom_board
    numbered["terminal"]["rows"] = %w[u u1]
    expect { Breadkit::BoardDef.new(numbered) }.to raise_error(ArgumentError, /ambiguous/i)
    bad_polarity = custom_board
    bad_polarity["rails"].first["polarity"] = "positive"
    expect { Breadkit::BoardDef.new(bad_polarity) }.to raise_error(ArgumentError, /polarity/i)
  end

  it "places DIP pins against a custom board ravine" do
    builder = Breadkit::DSL::Builder.new
    builder.document.board_definitions << custom_board
    builder.instance_eval('board :custom_grid; ic :U1, "NE555", at: "u1"', "sample.bk.rb", 1)
    circuit = Breadkit::Resolver.new.call(builder.document)
    expect(circuit.diagnostics).to be_empty
    expect(circuit.components.fetch("U1").pin("GND").hole_id).to eq("u1")
    expect(circuit.components.fetch("U1").pin("VCC").hole_id).to eq("v1")
  end

  it "validates part pin identities, polarity, footprints and library aliases" do
    base = { "id" => "custom", "pins" => [{ "num" => 1, "name" => "ANODE" }, { "num" => 2, "name" => "CATHODE" }] }
    expect { Breadkit::PartDef.new(base.merge("pins" => [{ "num" => 1, "name" => "A" }, { "num" => 1, "name" => "B" }])) }
      .to raise_error(ArgumentError, /duplicate pin/)
    expect { Breadkit::PartDef.new(base.merge("pins" => [{ "num" => 1, "name" => "A" }, { "num" => 2, "name" => "a" }])) }
      .to raise_error(ArgumentError, /duplicate pin/)
    expect { Breadkit::PartDef.new(base.merge("polarity" => { "positive" => "missing" })) }
      .to raise_error(ArgumentError, /polarity/)
    expect { Breadkit::PartDef.new(base.merge("footprint" => { "3" => [0, 0] })) }
      .to raise_error(ArgumentError, /footprint/)
    expect { Breadkit::PartDef.new(base.merge("footprint" => { "1" => [0] })) }
      .to raise_error(ArgumentError, /footprint/)
    expect { Breadkit::PartLibrary.new(extra_definitions: [base.merge("aliases" => ["led"])]) }
      .to raise_error(ArgumentError, /alias.*led/i)
    schema = JSONSchemer.schema(JSON.parse(File.read(File.expand_path("../schema/part-v1.json", __dir__))))
    expect(schema.valid?(base)).to be(true)
    expect(schema.valid?(base.merge("pins" => "bad"))).to be(false)
  end

  it "uses transistor model pinout and warns on an unknown model" do
    bc547 = Breadkit::Resolver.new.call(Breadkit::DSL::Builder.new.tap do |builder|
      builder.instance_eval('board :mini; transistor :Q1, "BC547", pins: %w[a1 a2 a3]', "sample.bk.rb", 1)
    end.document)
    expect(bc547.components.fetch("Q1").pins.values.map(&:name)).to eq(%w[collector base emitter])
    expect(bc547.components.fetch("Q1").part.data["transistor_polarity"]).to eq("NPN")
    pnp = Breadkit::PartLibrary.new.find("2N3906")
    expect(pnp.data["transistor_polarity"]).to eq("PNP")
    unknown = Breadkit::Resolver.new.call(Breadkit::DSL::Builder.new.tap do |builder|
      builder.instance_eval('board :mini; transistor :Q1, "unknown_123", pins: %w[a1 a2 a3]', "sample.bk.rb", 1)
    end.document)
    expect(unknown.diagnostics.map(&:code)).to include("unknown_transistor_model")
  end

  it "exposes Arduino Uno analog and power pins and ties its grounds" do
    part = Breadkit::PartLibrary.new.find("arduino_uno")
    %w[A0 A1 A2 A3 A4 A5 3V3 VIN GND2 GND3 RESET AREF].each do |name|
      expect(part.pin(name)).not_to be_nil
    end
    builder = Breadkit::DSL::Builder.new
    builder.instance_eval('board :mini; offboard :UNO, "arduino_uno"', "sample.bk.rb", 1)
    circuit = Breadkit::Resolver.new.call(builder.document)
    expect(circuit.net_of("UNO.GND")).to eq(circuit.net_of("UNO.GND2"))
  end

  it "records locations in a user DSL file named dsl.rb" do
    builder = Breadkit::DSL::Builder.new
    builder.instance_eval("board :mini\nresistor :R1, '1k', pins: %w[a1 a2]", "/tmp/dsl.rb", 1)
    expect(builder.document.components.first[:location].line).to eq(2)
  end

  it "requires terminal groups to partition rows and the ravine to use adjacent rows" do
    duplicate = custom_board
    duplicate["terminal"]["groups"] = [%w[u], %w[u v]]
    expect { Breadkit::BoardDef.new(duplicate) }.to raise_error(ArgumentError, /groups/)
    missing = custom_board
    missing["terminal"]["groups"] = [%w[u]]
    expect { Breadkit::BoardDef.new(missing) }.to raise_error(ArgumentError, /groups/)
    unknown = custom_board
    unknown["terminal"]["groups"] = [%w[u], %w[v x]]
    expect { Breadkit::BoardDef.new(unknown) }.to raise_error(ArgumentError, /groups/)
    ravine = custom_board
    ravine["terminal"]["ravine_between"] = %w[u x]
    expect { Breadkit::BoardDef.new(ravine) }.to raise_error(ArgumentError, /ravine/)
    reversed = custom_board
    reversed["terminal"]["ravine_between"] = %w[v u]
    expect { Breadkit::BoardDef.new(reversed) }.to raise_error(ArgumentError, /ravine/)
  end

  it "rejects misspelled and nonboolean board options" do
    expect { Breadkit::DSL::Builder.new.instance_eval('board :full, splt_rails: true', "sample.bk.rb", 1) }
      .to raise_error(Breadkit::DSLError, /splt_rails/)
    expect { Breadkit::DSL::Builder.new.instance_eval('board :full, split_rails: "false"', "sample.bk.rb", 1) }
      .to raise_error(Breadkit::DSLError, /split_rails.*boolean/)
    expect { Breadkit::DSL::Builder.new.instance_eval('board :full, split_rails: false', "sample.bk.rb", 1) }
      .not_to raise_error
  end

  it "reports unrecognized part and offboard attributes as errors" do
    builder = Breadkit::DSL::Builder.new
    builder.instance_eval('board :mini; resistor :R1, "1k", pins: %w[a1 a2], not_a_real_option: 7; offboard :UNO, "arduino_uno", invented: true', "sample.bk.rb", 1)
    circuit = Breadkit::Resolver.new.call(builder.document)
    errors = circuit.diagnostics.select { |diagnostic| diagnostic.severity == "error" }
    expect(errors.map(&:code)).to include("unknown_option")
    expect(errors.map(&:message).join(" ")).to include("not_a_real_option", "invented")
  end

  it "reports unknown part options on stderr and fails the IR command" do
    require "tempfile"
    Tempfile.create(["breadkit-option", ".bk.rb"]) do |file|
      file.write("board :mini\nresistor :R1, '1k', pins: %w[a1 a2], not_a_real_option: 7\n")
      file.flush
      status = nil
      expect { status = Breadkit::CLI.new.run(["ir", file.path]) }
        .to output(/unknown_option.*not_a_real_option/).to_stderr
      expect(status).to eq(1)
    end
  end
end
