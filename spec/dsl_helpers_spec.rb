# frozen_string_literal: true

require "json_schemer"
require "tmpdir"

RSpec.describe "DSL block and bus helpers" do
  def circuit(source)
    builder = Breadkit::DSL::Builder.new
    builder.instance_eval(source, "helpers.bk.rb", 1)
    Breadkit::Resolver.new.call(builder.document)
  end

  it "expands a named block into ordinary part declarations on each use" do
    helper = <<~RUBY
      board :mini
      block :indicator do |number, resistor_pins:, led_pins:|
        resistor "R\#{number}", "330", pins: resistor_pins
        led "D\#{number}", color: :red, **led_pins
      end
      use_block :indicator, 1, resistor_pins: %w[a1 a3], led_pins: {anode: "b3", cathode: "b4"}
      use_block :indicator, 2, resistor_pins: %w[a6 a8], led_pins: {anode: "b8", cathode: "b9"}
    RUBY
    explicit = <<~RUBY
      board :mini
      resistor :R1, "330", pins: %w[a1 a3]
      led :D1, color: :red, anode: "b3", cathode: "b4"
      resistor :R2, "330", pins: %w[a6 a8]
      led :D2, color: :red, anode: "b8", cathode: "b9"
    RUBY
    expanded = circuit(helper)
    original = circuit(explicit)
    expect(expanded.diagnostics).to be_empty
    expect(expanded.components.keys).to eq(%w[R1 D1 R2 D2])
    expect(expanded.nets.map { |net| [net.name, net.members] }).to eq(original.nets.map { |net| [net.name, net.members] })
    ir = expanded.to_ir
    schema = JSONSchemer.schema(JSON.parse(File.read(File.expand_path("../schema/ir-v1.json", __dir__))))
    expect(schema.valid?(ir)).to be(true)
    expect(Breadkit::IR::Reader.new.read(ir).to_ir).to eq(ir)
  end

  it "labels explicitly supplied bus lines without adding wires" do
    grouped = circuit('board :half; bus :I2C, scl: "f22", sda: "f24"')
    explicit = circuit('board :half; net :I2C_SCL, at: "f22"; net :I2C_SDA, at: "f24"')
    expect(grouped.diagnostics).to be_empty
    expect(grouped.labels.map(&:name)).to eq(%w[I2C_SCL I2C_SDA])
    expect(grouped.wires).to be_empty
    expect(grouped.nets.map { |net| [net.name, net.members] }).to eq(explicit.nets.map { |net| [net.name, net.members] })
  end

  it "uses blocks defined in an included DSL file" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "parts.bk.rb"), 'block(:series_resistor) { |ref, holes| resistor ref, "330", pins: holes }')
      main = File.join(dir, "main.bk.rb")
      File.write(main, "board :mini\ninclude \"parts.bk.rb\"\nuse_block :series_resistor, :R1, %w[a1 a3]\n")
      result = Breadkit.load(main)
      expect(result.diagnostics).to be_empty
      expect(result.components).to have_key("R1")
    end
  end

  it "rejects missing, duplicate, unknown, or recursive block declarations" do
    builder = Breadkit::DSL::Builder.new
    expect { builder.instance_eval('block :missing', "helpers.bk.rb", 1) }
      .to raise_error(Breadkit::DSLError, /requires a body/)
    builder.instance_eval('block(:a) { resistor :R1, "330", pins: %w[a1 a3] }', "helpers.bk.rb", 1)
    expect { builder.instance_eval('block(:a) {}', "helpers.bk.rb", 1) }
      .to raise_error(Breadkit::DSLError, /already defined/)
    expect { builder.instance_eval('use_block :unknown', "helpers.bk.rb", 1) }
      .to raise_error(Breadkit::DSLError, /unknown block/)
    builder.instance_eval('block(:loop) { use_block :loop }', "helpers.bk.rb", 1)
    expect { builder.instance_eval('use_block :loop', "helpers.bk.rb", 1) }
      .to raise_error(Breadkit::DSLError, /recursive block/)
  end

  it "rejects a bus without valid line names and hole references" do
    builder = Breadkit::DSL::Builder.new
    expect { builder.instance_eval('bus :I2C', "helpers.bk.rb", 1) }
      .to raise_error(Breadkit::DSLError, /at least one line/)
    expect { builder.instance_eval('bus :I2C, "S DA" => "a1"', "helpers.bk.rb", 1) }
      .to raise_error(Breadkit::DSLError, /invalid bus line/)
    expect { builder.instance_eval('bus :I2C, scl: 22', "helpers.bk.rb", 1) }
      .to raise_error(Breadkit::DSLError, /reference must be text/)
    expect { builder.instance_eval('bus :I2C, scl: "a1", SCL: "a2"', "helpers.bk.rb", 1) }
      .to raise_error(Breadkit::DSLError, /duplicate bus line/)
  end
end
