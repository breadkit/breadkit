# frozen_string_literal: true

require "tempfile"

RSpec.describe "circuit input validation" do
  def circuit(source)
    builder = Breadkit::DSL::Builder.new
    builder.instance_eval(source, "sample.bk.rb", 1)
    Breadkit::Resolver.new.call(builder.document)
  end

  it "reports DSL mistakes with their source line" do
    Tempfile.create(["breadkit", ".bk.rb"]) do |file|
      file.write("board :mini\nregistor :R1, '330'\n")
      file.flush
      expect { Breadkit.load(file.path) }.to raise_error(Breadkit::DSLError) { |error|
        expect(error.location.line).to eq(2)
        expect(error.message).to include("#{file.path}:2:")
      }
    end
  end

  it "contains exit and runaway evaluation" do
    Tempfile.create(["breadkit", ".bk.rb"]) do |file|
      file.write("exit 3\n")
      file.flush
      expect { Breadkit.load(file.path) }.to raise_error(Breadkit::DSLError, /exit is not allowed/)
      file.rewind
      file.truncate(0)
      file.write("loop {}\n")
      file.flush
      expect { Breadkit.load(file.path, timeout: 0.01) }.to raise_error(Breadkit::DSLError, /timed out/)
    end
  end

  it "validates values, part attributes, colors, routes, and wire IDs" do
    result = circuit(<<~RUBY)
      board :mini
      resistor :R1, "33O", pins: %w[a1 a3]
      resistor :R2, "330", pins: %w[b1 b3], bands: 5
      led :D1, anode: "c1", cathode: "c3", color: :warmwhite
      wire "a2", "b2", color: :rde, route: :curvy, id: "a20"
    RUBY
    expect(result.diagnostics.map(&:code)).to include("invalid_value", "invalid_color", "invalid_route", "invalid_wire_id")
    expect(result.diagnostics.map(&:code)).not_to include("unknown_option")
  end

  it "warns when no part files match and permits an explicit built-in override" do
    Tempfile.create(["breadkit-part", ".yml"]) do |file|
      file.write(<<~YAML)
        id: led
        override: true
        category: diode
        placement: leads
        pins:
          - {num: 1, name: anode}
          - {num: 2, name: cathode}
      YAML
      file.flush
      result = circuit("use_parts #{file.path.inspect}\nuse_parts 'missing-part-*.yml'\nled :D1, anode: 'a1', cathode: 'a3'")
      expect(result.diagnostics.map(&:code)).to include("part_override", "unmatched_parts")
      expect(result.diagnostics.map(&:severity)).not_to include("error")
    end
  end

  it "rejects misspelled part definition fields" do
    part = { "id" => "custom", "pins" => [{ "num" => 1 }] }
    expect { Breadkit::PartDef.new(part.merge("straddel" => true)) }.to raise_error(ArgumentError, /straddel/)
    expect { Breadkit::PartDef.new(part.merge("pins" => [{ "num" => 1, "typo" => "power" }])) }
      .to raise_error(ArgumentError, /typo/)
    expect { Breadkit::PartDef.new(part.merge("attributes" => [1])) }.to raise_error(ArgumentError, /attributes/)
    expect { Breadkit::PartDef.new(part.merge("render" => { "colr" => "red" })) }.to raise_error(ArgumentError, /colr/)
    expect { Breadkit::PartDef.new(part.merge("pins" => [{ "num" => 1, "label" => [1] }])) }
      .to raise_error(ArgumentError, /label/)
    expect { Breadkit::PartDef.new(part.merge("pins" => [{ "num" => 1, "max_voltage" => Float::INFINITY }])) }
      .to raise_error(ArgumentError, /max_voltage/)
    expect { Breadkit::PartDef.new(part.merge("provides" => [{ "positive" => 1, "negative" => 1, "voltage" => Float::INFINITY }])) }
      .to raise_error(ArgumentError, /voltage source/)
  end

  it "checks CSS colors even when a custom part declares a color enum" do
    custom = { "id" => "custom", "pins" => [{ "num" => 1 }], "attributes" => { "color" => ["rde"] } }
    builder = Breadkit::DSL::Builder.new
    builder.document.part_definitions << custom
    builder.part(:P1, :custom, nil, pins: ["a1"], color: :rde)
    expect(Breadkit::Resolver.new.call(builder.document).diagnostics.map(&:code)).to include("invalid_color")
  end

  it "detects shorts from offboard power outputs once per source pair" do
    result = circuit("board :mini\noffboard :UNO, :arduino_uno\nwire 'UNO.5V', 'UNO.GND'")
    expect(result.potentials.conflicts.length).to eq(1)
    expect(result.potentials.conflicts.first[:supply].name).to eq("UNO.5V")
  end

  it "preserves isolated ranged supplies through IR" do
    result = circuit("board :mini\nsupply :CELL, voltage: 3.0..4.2, plus: 'a1', minus: 'a2', isolated: true")
    source = result.supplies.first
    expect(source.voltage).to eq(3.6)
    expect(source.voltage_range).to eq([3.0, 4.2])
    expect(source.isolated).to be(true)
    restored = Breadkit::IR::Reader.new.read(result.to_ir)
    expect(restored.supplies.first.voltage_range).to eq([3.0, 4.2])
    expect(restored.supplies.first.isolated).to be(true)
    expect { circuit("supply :CELL, voltage: 4.2...3.0, plus: 'a1', minus: 'a2'") }
      .to raise_error(Breadkit::DSLError, /inclusive and ascending/)
  end

  it "preserves a positive supply current limit through IR" do
    result = circuit("board :mini\nsupply :CELL, voltage: 3.7, current_limit: 0.02, plus: 'a1', minus: 'a2'")
    expect(result.supplies.first.current_limit).to eq(0.02)
    data = Breadkit::IR::Writer.new.write(result)
    expect(data[:supplies].first[:current_limit]).to eq(0.02)
    expect(Breadkit::IR::Reader.new.read(data).supplies.first.current_limit).to eq(0.02)
    data[:supplies].first[:current_limit] = -1
    expect { Breadkit::IR::Reader.new.read(data) }.to raise_error(Breadkit::DSLError, /current_limit/)
    expect { circuit("board :mini\nsupply :CELL, voltage: 3.7, current_limit: 0, plus: 'a1', minus: 'a2'") }
      .to raise_error(Breadkit::DSLError, /current_limit/)
    expect { circuit("board :mini\nsupply :CELL, voltage: 3.7, current_limit: false, plus: 'a1', minus: 'a2'") }
      .to raise_error(Breadkit::DSLError, /current_limit/)
    expect { circuit("board :mini\nsupply :CELL, voltage: 3.7, current_limit: 1+1i, plus: 'a1', minus: 'a2'") }
      .to raise_error(Breadkit::DSLError, /current_limit/)
  end

  it "keeps IR source paths stable across working directories" do
    path = File.expand_path("../examples/01_led_button.bk.rb", __dir__)
    ir = Breadkit.load(path).to_ir
    expect(ir[:source_root]).to eq(File.dirname(path))
    expect(ir[:components].first[:source][:path]).to eq(File.basename(path))
    restored = Breadkit::IR::Reader.new.read(ir)
    expect(restored.components.values.first.location.path).to eq(path)
  end

  it "rotates and mirrors footprint pins around their anchor" do
    placements = {
      [0, false] => %w[c10 c11 d10],
      [90, false] => %w[c10 d10 c9],
      [180, false] => %w[c10 c9 b10],
      [270, false] => %w[c10 b10 c11],
      [0, true] => %w[c10 c9 d10]
    }
    placements.each do |(rotate, mirror), expected|
      builder = Breadkit::DSL::Builder.new
      builder.document.part_definitions << { "id" => "asymmetric", "placement" => "footprint",
        "pins" => (1..3).map { |number| { "num" => number } },
        "footprint" => { "1" => [0, 0], "2" => [1, 0], "3" => [0, 1] } }
      builder.instance_eval("board :mini; part :U1, :asymmetric, at: 'c10', rotate: #{rotate}, mirror: #{mirror}", "sample.bk.rb", 1)
      result = Breadkit::Resolver.new.call(builder.document)
      expect(result.diagnostics).to be_empty
      expect(result.components.fetch("U1").pins.values.map(&:hole_id)).to eq(expected)
      restored = Breadkit::IR::Reader.new.read(result.to_ir)
      expect(restored.components.fetch("U1").attrs).to include(rotate: rotate, mirror: mirror)
    end
  end

  it "checks rotated explicit pins and reports an out-of-board footprint once" do
    builder = Breadkit::DSL::Builder.new
    builder.document.part_definitions << { "id" => "asymmetric", "placement" => "footprint",
      "pins" => (1..3).map { |number| { "num" => number } },
      "footprint" => { "1" => [0, 0], "2" => [1, 0], "3" => [0, 1] } }
    builder.instance_eval("board :mini; part :U1, :asymmetric, pins: %w[c10 d10 c9], rotate: 90", "sample.bk.rb", 1)
    expect(Breadkit::Resolver.new.call(builder.document).diagnostics).to be_empty
    builder.document.components.first[:pins] = %w[c10 c11 d10]
    expect(Breadkit::Resolver.new.call(builder.document).diagnostics.map(&:code)).to include("invalid_placement")
    builder.document.components.first[:pins] = nil
    builder.document.components.first[:at] = "a1"
    builder.document.components.first[:attrs] = { rotate: 180 }
    errors = Breadkit::Resolver.new.call(builder.document).diagnostics.select { |entry| entry.code == "invalid_placement" }
    expect(errors.length).to eq(1)
  end

  it "treats the anchor as pin one even when its footprint offset is nonzero" do
    builder = Breadkit::DSL::Builder.new
    builder.document.part_definitions << { "id" => "offset", "placement" => "footprint",
      "pins" => (1..3).map { |number| { "num" => number } },
      "footprint" => { "1" => [1, 0], "2" => [2, 0], "3" => [1, 1] } }
    builder.instance_eval("board :mini; part :U1, :offset, at: 'c10', rotate: 90", "sample.bk.rb", 1)
    result = Breadkit::Resolver.new.call(builder.document)
    expect(result.diagnostics).to be_empty
    expect(result.components.fetch("U1").pins.values.map(&:hole_id)).to eq(%w[c10 d10 c9])
  end
end
