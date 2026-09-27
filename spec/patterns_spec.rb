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
end
