# frozen_string_literal: true

RSpec.describe "circuit patterns" do
  def resolve(source)
    builder = Breadkit::DSL::Builder.new
    builder.instance_eval(source, "patterns.bk.rb", 1)
    Breadkit::Resolver.new.call(builder.document)
  end

  let(:divider) do
    resolve('board :mini; supply :BAT, voltage: 6, plus: "b1", minus: "b5"; resistor :R1, "1k", pins: %w[a1 a3]; resistor :R2, "2k", pins: %w[b3 a5]')
  end

  it "exposes a circuit pattern recognizer" do
    expect(defined?(Breadkit::Patterns)).to eq("constant")
  end

  it "recognizes an unloaded two-resistor divider and reports DC midpoint voltage" do
    result = Breadkit::Patterns.call(divider).fetch(0)

    expect(result).to include("kind" => "voltage_divider", "supply" => "BAT",
                              "top_resistor" => "R1", "bottom_resistor" => "R2",
                              "midpoint_net" => divider.net_of("a3").name,
                              "reference" => "BAT.-")
    expect(result.fetch("midpoint_voltage_v")).to be_within(1e-9).of(4.0)
    expect(result.fetch("explanation")).to include("unloaded", "supply negative")
  end

  it "does not identify a loaded or ambiguous circuit as an unloaded divider" do
    loaded = resolve('board :mini; supply :BAT, voltage: 6, plus: "b1", minus: "b5"; resistor :R1, "1k", pins: %w[a1 a3]; resistor :R2, "2k", pins: %w[b3 a5]; resistor :LOAD, "1k", pins: %w[c3 b5]')
    multiple_sources = resolve('board :mini; supply :BAT, voltage: 6, plus: "b1", minus: "b5"; supply :AUX, voltage: 3, plus: "b7", minus: "b8"; resistor :R1, "1k", pins: %w[a1 a3]; resistor :R2, "2k", pins: %w[b3 a5]')
    parallel = resolve('board :mini; supply :BAT, voltage: 6, plus: "b1", minus: "b5"; resistor :R1, "1k", pins: %w[a1 a5]; resistor :R2, "2k", pins: %w[c1 c5]')
    ranged = resolve('board :mini; supply :BAT, voltage: 3.0..4.2, plus: "b1", minus: "b5"; resistor :R1, "1k", pins: %w[a1 a3]; resistor :R2, "2k", pins: %w[b3 a5]')

    [loaded, multiple_sources, parallel, ranged].each do |circuit|
      expect(Breadkit::Patterns.call(circuit)).to eq([])
    end
  end

  it "reports only explicit matches from the CLI" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "divider.bk.rb")
      File.write(path, 'board :mini; supply :BAT, voltage: 6, plus: "b1", minus: "b5"; resistor :R1, "1k", pins: %w[a1 a3]; resistor :R2, "2k", pins: %w[b3 a5]')
      expect { expect(Breadkit::CLI.new.run(["patterns", path])).to eq(0) }
        .to output(/"kind": "voltage_divider"/).to_stdout

      File.write(path, "board :mini; resistor :R1, '1k', pins: %w[a1 a3]")
      expect { expect(Breadkit::CLI.new.run(["patterns", path])).to eq(0) }
        .to output("[]\n").to_stdout
    end
  end

  it "recognizes the documented NE555 astable LED wiring without inventing a frequency" do
    circuit = Breadkit.load(File.expand_path("../examples/02_555_blinker.bk.rb", __dir__))
    patterns = Breadkit::Patterns.call(circuit)

    expect(patterns.map { |pattern| pattern.fetch("kind") }).to include("ne555_astable_wiring")
    expect(patterns.first).to include("timer" => "U1", "supply" => "USB",
                                     "charge_resistor" => "R1", "discharge_resistor" => "R2",
                                     "timing_capacitor" => "C2", "output_resistor" => "R3",
                                     "output_led" => "D1")
    expect(patterns.first).not_to have_key("frequency_hz")
    expect(patterns.first.fetch("explanation")).to include("wiring matches", "not a simulation")
  end

  it "rejects incomplete or modified NE555 timing and output connections" do
    source = File.read(File.expand_path("../examples/02_555_blinker.bk.rb", __dir__)).split(/\nexpect do/).first
    variants = [
      source.sub('wire "g20", "T+20", color: :red', ''),
      source.sub('resistor :R2, "10k", pins: %w[h21 h22]', 'resistor :R2, "10k", pins: %w[h21 h26]'),
      source + "\nwire \"j23\", \"B+\"\n",
      source.sub('led :D1, color: :red, anode: "b25", cathode: "b27"',
                 'led :D1, color: :red, anode: "b27", cathode: "b25"'),
      source.sub('electrolytic :C2, "100u", plus: "g22", minus: "j24"',
                 'electrolytic :C2, "100u", plus: "j24", minus: "g22"'),
      source.sub('supply :USB, voltage: 5.0', 'supply :USB, voltage: 3.0..4.2'),
      source.sub('supply :USB, voltage: 5.0', 'supply :USB, voltage: 3.3'),
      source + "\nresistor :LOAD, \"1k\", pins: %w[i21 i26]\nwire \"j26\", \"B-\"\n"
    ]

    variants.each do |modified|
      circuit = resolve(modified)
      expect(circuit.diagnostics.select { |item| item.severity == "error" }).to be_empty
      expect(Breadkit::Patterns.call(circuit)).to eq([])
    end
  end
end
