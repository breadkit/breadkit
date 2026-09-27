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

  it "keeps IR source paths stable across working directories" do
    path = File.expand_path("../examples/01_led_button.bk.rb", __dir__)
    ir = Breadkit.load(path).to_ir
    expect(ir[:source_root]).to eq(File.dirname(path))
    expect(ir[:components].first[:source][:path]).to eq(File.basename(path))
    restored = Breadkit::IR::Reader.new.read(ir)
    expect(restored.components.values.first.location.path).to eq(path)
  end
end
