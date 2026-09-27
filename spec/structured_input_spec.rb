# frozen_string_literal: true

require "tmpdir"

RSpec.describe "declarative circuit files" do
  let(:ruby_source) do
    <<~RUBY
      title "LED circuit"
      board :mini
      supply :USB, voltage: 5, plus: "a1", minus: "a2"
      net :VCC, at: "a1"
      net :GND, at: "a2"
      resistor :R1, "330", pins: %w[b1 b3]
      led :D1, color: :red, anode: "c3", cathode: "c4"
      wire "d4", "b2", color: :black
      expect do
        connected :VCC, "R1.1"
        connected "R1.2", "D1.anode"
        connected "D1.cathode", :GND
      end
    RUBY
  end
  let(:yaml_source) do
    <<~YAML
      title: LED circuit
      board: mini
      supplies:
        - {name: USB, voltage: 5, plus: a1, minus: a2}
      labels:
        - {name: VCC, at: a1}
        - {name: GND, at: a2}
      parts:
        - {ref: R1, type: resistor, value: "330", pins: [b1, b3]}
        - {ref: D1, type: led, pins: {anode: c3, cathode: c4}, attrs: {color: red}}
      wires:
        - {from: d4, to: b2, color: black}
      expectations:
        - connected: [[VCC, R1.1], [R1.2, D1.anode], [D1.cathode, GND]]
    YAML
  end
  let(:toml_source) do
    <<~TOML
      title = "LED circuit"
      board = "mini"
      [[supplies]]
      name = "USB"
      voltage = 5
      plus = "a1"
      minus = "a2"
      [[labels]]
      name = "VCC"
      at = "a1"
      [[labels]]
      name = "GND"
      at = "a2"
      [[parts]]
      ref = "R1"
      type = "resistor"
      value = "330"
      pins = ["b1", "b3"]
      [[parts]]
      ref = "D1"
      type = "led"
      pins = { anode = "c3", cathode = "c4" }
      attrs = { color = "red" }
      [[wires]]
      from = "d4"
      to = "b2"
      color = "black"
      [[expectations]]
      connected = [["VCC", "R1.1"], ["R1.2", "D1.anode"], ["D1.cathode", "GND"]]
    TOML
  end

  it "resolves YAML and TOML to the same circuit as Ruby DSL" do
    Dir.mktmpdir do |dir|
      paths = { ruby: "sample.bk.rb", yaml: "sample.bk.yml", toml: "sample.bk.toml" }
      paths.each { |kind, name| File.write(File.join(dir, name), public_send("#{kind}_source")) }
      circuits = paths.transform_values { |name| Breadkit.load(File.join(dir, name)) }
      expect(circuits.values.flat_map(&:diagnostics)).to be_empty
      expected = circuits.fetch(:ruby).nets.map { |net| [net.name, net.members] }
      expect(circuits.fetch(:yaml).nets.map { |net| [net.name, net.members] }).to eq(expected)
      expect(circuits.fetch(:toml).nets.map { |net| [net.name, net.members] }).to eq(expected)
      expect(circuits.fetch(:yaml).components.keys).to eq(%w[R1 D1])
      expect(circuits.fetch(:toml).expectations.first[:entries].length).to eq(3)
    end
  end

  it "rejects tagged YAML objects and unknown declarations without evaluating them" do
    Dir.mktmpdir do |dir|
      tagged = File.join(dir, "tagged.bk.yml")
      File.write(tagged, "title: !ruby/object:Object {}\n")
      expect { Breadkit.load(tagged) }.to raise_error(Breadkit::DSLError, /tagged\.bk\.yml/)
      typo = File.join(dir, "typo.bk.toml")
      File.write(typo, "board = \"mini\"\n[[wires]]\nfrom = \"a1\"\nto = \"a2\"\ncolour = \"red\"\n")
      expect { Breadkit.load(typo) }.to raise_error(Breadkit::DSLError, /wires\[0\].*colour/)
    end
  end

  it "supports offboard declarations, custom part paths, and inclusive voltage ranges" do
    Dir.mktmpdir do |dir|
      yaml = File.join(dir, "module.bk.yml")
      File.write(File.join(dir, "sensor.yml"), "id: sensor\nplacement: offboard\npins: [{num: 1, name: SIG}]\n")
      File.write(yaml, <<~YAML)
        board: mini
        use_parts: [sensor.yml]
        supplies:
          - {name: BAT, voltage: "3.0..4.2", plus: a1, minus: a2, isolated: true}
        offboard:
          - {ref: SENSOR, type: sensor}
        wires:
          - {from: SENSOR.SIG, to: b1}
      YAML
      result = Breadkit.load(yaml)
      expect(result.diagnostics.select { |item| item.severity == "error" }).to be_empty
      expect(result.supplies.first.voltage_range).to eq([3.0, 4.2])
      expect(result.components).to have_key("SENSOR")
      expect(result.net_of("SENSOR.SIG")).to eq(result.net_of("a1"))
    end
  end

  it "recognizes only explicit declarative circuit extensions" do
    Dir.mktmpdir do |dir|
      long_yaml = File.join(dir, "sample.bk.yaml")
      File.write(long_yaml, "board: mini\n")
      expect(Breadkit.load(long_yaml).board.definition.id).to eq("mini")

      plain_yaml = File.join(dir, "part.yml")
      File.write(plain_yaml, "id: sensor\npins: []\n")
      expect { Breadkit.load(plain_yaml) }.to raise_error(Breadkit::DSLError, /part\.yml/)
    end
  end

  it "rejects YAML aliases, malformed shapes, and invalid expectation ranges" do
    Dir.mktmpdir do |dir|
      aliases = File.join(dir, "alias.bk.yaml")
      File.write(aliases, "board: &name mini\ntitle: *name\n")
      expect { Breadkit.load(aliases) }.to raise_error(Breadkit::DSLError, /alias\.bk\.yaml/)

      shape = File.join(dir, "shape.bk.toml")
      File.write(shape, "title = \"test\"\nparts = \"resistor\"\n")
      expect { Breadkit.load(shape) }.to raise_error(Breadkit::DSLError, /root\.parts must be a list/)

      range = File.join(dir, "range.bk.yml")
      File.write(range, "expectations:\n  - voltage: [{ref: a1, range: '5..3'}]\n")
      expect { Breadkit.load(range) }.to raise_error(Breadkit::DSLError, /range is invalid/)
    end
  end

  it "keeps the published YAML and TOML examples equivalent" do
    example_dir = File.expand_path("../examples", __dir__)
    yaml = Breadkit.load(File.join(example_dir, "06_declarative_led.bk.yml"))
    toml = Breadkit.load(File.join(example_dir, "07_declarative_led.bk.toml"))
    expect(yaml.diagnostics).to be_empty
    expect(toml.diagnostics).to be_empty
    expect(toml.nets.map { |net| [net.name, net.members] }).to eq(yaml.nets.map { |net| [net.name, net.members] })
  end

  it "accepts board options, current limits, and measurement expectations" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "options.bk.yaml")
      File.write(path, <<~YAML)
        board: {type: full, split_rails: true}
        supplies:
          - {name: BAT, voltage: "3.0..4.2", plus: a1, minus: a2, current_limit: 0.25}
        expectations:
          - strict: true
            nets: [{name: BAT, refs: [a1]}]
            voltage: [{ref: a1, range: "3.0..4.2"}]
            current: [{ref: BAT, range: "0..0.25"}]
        lint_disables:
          - {rule: floating_pin, "on": BAT, reason: test}
      YAML
      document = Breadkit::StructuredInput.load_file(path)
      expect(document.board.fetch(:options).fetch(:split_rails)).to be(true)
      expect(document.supplies.first.fetch(:current_limit)).to eq(0.25)
      expect(document.expectations.first.fetch(:entries).map { |entry| entry.fetch(:kind) }).to eq(%w[net voltage current])
      expect(document.expectations.first.fetch(:entries).last.fetch(:range)).to eq([0.0, 0.25])
      expect(document.lint_disables.first.fetch(:rule)).to eq("floating_pin")
    end
  end
end
