# frozen_string_literal: true

require "tmpdir"

RSpec.describe Breadkit::Lint::Engine do
  let(:examples) { File.expand_path("../../../examples", __dir__) }

  it "leaves the valid LED and NE555 examples clean" do
    files = %w[01_led_button.bk.rb 02_555_blinker.bk.rb 03_arduino_blink.bk.rb 04_led_bar.bk.rb].map { |name| File.join(examples, name) }
    results = described_class.new.run(files)
    expect(results.map { |item| item[:offenses] }).to all(be_empty)
  end

  it "reports the expected offenses for each broken example" do
    expected = {
      "short_circuit.bk.rb" => "Electrical/ShortCircuit",
      "resistor_same_column.bk.rb" => "Layout/PinsInSameStrip",
      "floating_led.bk.rb" => "Electrical/FloatingPin",
      "ic_not_straddling.bk.rb" => "Layout/InvalidPlacement"
    }
    expected.each do |file, rule|
      result = described_class.new.run([File.join(examples, "bad", file)]).first
      expect(result[:offenses].map(&:rule)).to include(rule)
    end
  end

  it "emits JSON in the format consumed by the renderer" do
    files = described_class.new.run([File.join(examples, "bad", "short_circuit.bk.rb")])
    parsed = JSON.parse(Breadkit::Lint::Formatter.new.json(files))
    expect(parsed.dig("schema_version")).to eq(1)
    expect(parsed.dig("files", 0, "offenses", 0, "targets")).to be_a(Hash)
    expect(parsed.dig("summary", "errors")).to be > 0
  end

  it "respects the fail level and rule selection" do
    path = File.join(examples, "bad", "resistor_same_column.bk.rb")
    config = Breadkit::Lint::Config.new
    engine = described_class.new(config: config)
    errors = engine.run([path], only: ["Layout/PinsInSameStrip"])
    expect(engine.fail?(errors, "warning")).to be(true)
    warnings = [
      { path: path, offenses: [Breadkit::Lint::Offense.new(rule: "test", severity: "warning", message: "w", targets: {})] }
    ]
    expect(engine.fail?(warnings, "error")).to be(false)
  end

  it "keeps default settings aligned with registered rules and warns on misspellings" do
    config = Breadkit::Lint::Config.new
    configured = config.data.keys - ["AllRules"]
    expect(configured.sort).to eq(Breadkit::Lint::Registry.all.map(&:id).sort)
    Dir.mktmpdir do |directory|
      path = File.join(directory, ".bklint.yml")
      File.write(path, "Layout/PinInSameStrip:\n  Severity: warning\n")
      expect(Breadkit::Lint::Config.new(path).unknown_rules).to include("Layout/PinInSameStrip")

      base = File.join(directory, "base.yml")
      child = File.join(directory, "child.yml")
      File.write(base, "AllRules:\n  FailLevel: error\n  Exclude: ['*.bk.rb']\n")
      File.write(child, "inherit_from:\n  - ./base.yml\nAllRules:\n  SwitchStates: none\n")
      inherited = Breadkit::Lint::Config.new(child)
      expect(inherited.fail_level).to eq("error")
      expect(inherited.switch_states).to eq("none")
      expect(inherited.excluded?(File.join(directory, "example.bk.rb"))).to be(true)
    end
  end

  it "reports unknown intent nets through the configured rule ID" do
    Dir.mktmpdir do |directory|
      path = File.join(directory, "unknown.bk.rb")
      File.write(path, "board :half\nexpect { connected :MISSING, :ALSO_MISSING }\n")
      offenses = described_class.new.run([path]).first[:offenses]
      expect(offenses.map(&:rule)).to include("Intent/UnknownNet")
    end
  end

  it "checks bypassed parts, conflicting labels, and declared wiring intent" do
    sources = {
      "bypassed.bk.rb" => "board :mini\nresistor :R1, '330', pins: %w[a1 a2]\nwire 'b1', 'b2'\n",
      "labels.bk.rb" => "board :half\nsupply :P, voltage: 5, plus: 'B+1', minus: 'B-1'\nnet :VCC, at: 'B+1'\nnet :GND, at: 'B-1'\nwire 'a10', 'B+'\nwire 'b10', 'B-'\n",
      "intent.bk.rb" => "board :mini\nresistor :R1, '330', pins: %w[a1 a2]\nexpect { connected 'R1.1', 'R1.2' }\n"
    }
    Dir.mktmpdir do |directory|
      sources.each do |name, source|
        path = File.join(directory, name)
        File.write(path, source)
      end
      rules = sources.keys.flat_map do |name|
        described_class.new.run([File.join(directory, name)]).first[:offenses].map(&:rule)
      end
      expect(rules).to include("Electrical/ShortedComponent", "Electrical/NetLabelConflict", "Intent/ConnectionMismatch")
    end
  end

  it "checks polarity, series resistance, IC voltage, common ground, split rails, and wire colors" do
    sources = {
      "series.bk.rb" => "board :half\nsupply :P, voltage: 5, plus: 'B+1', minus: 'B-1'\nled :D1, anode: 'b10', cathode: 'g12'\nwire 'a10', 'B+'\nwire 'h12', 'B-'\n",
      "series_zero.bk.rb" => "board :half\nsupply :P, voltage: 5, plus: 'B+1', minus: 'B-1'\nled :D1, anode: 'b10', cathode: 'g12'\nresistor :R1, '0', pins: %w[c10 i12]\nwire 'a10', 'B+'\nwire 'h12', 'B-'\n",
      "reverse.bk.rb" => "board :half\nsupply :P, voltage: 5, plus: 'B+1', minus: 'B-1'\nled :D1, anode: 'b10', cathode: 'g12'\nwire 'a10', 'B-'\nwire 'h12', 'B+'\n",
      "range.bk.rb" => "board :half\nsupply :P, voltage: 3.3, plus: 'B+1', minus: 'B-1'\nic :U1, 'NE555', at: 'e20'\nwire 'U1.8', 'B+'\nwire 'U1.1', 'B-'\n",
      "unconnected.bk.rb" => "board :half\nsupply :P, voltage: 5, plus: 'B+1', minus: 'B-1'\nic :U1, 'NE555', at: 'e20'\n",
      "grounds.bk.rb" => "board :half\nsupply :P1, voltage: 5, plus: 'B+1', minus: 'B-1'\nsupply :P2, voltage: 3.3, plus: 'T+1', minus: 'T-1'\n",
      "split.bk.rb" => "board :full, split_rails: true\nsupply :P, voltage: 5, plus: 'B+1', minus: 'B-1'\nwire 'a10', 'B+30'\n",
      "color.bk.rb" => "board :half\nsupply :P, voltage: 5, plus: 'B+1', minus: 'B-1'\nwire 'a10', 'B+', color: :blue\n"
    }
    expected = {
      "series.bk.rb" => "Electrical/MissingSeriesResistor",
      "series_zero.bk.rb" => "Electrical/MissingSeriesResistor",
      "reverse.bk.rb" => "Electrical/ReversePolarity",
      "range.bk.rb" => "Electrical/SupplyVoltageRange",
      "unconnected.bk.rb" => "Electrical/PowerPinUnconnected",
      "grounds.bk.rb" => "Electrical/NoCommonGround",
      "split.bk.rb" => "Electrical/SplitRail",
      "color.bk.rb" => "Style/WireColor"
    }
    Dir.mktmpdir do |directory|
      sources.each { |name, source| File.write(File.join(directory, name), source) }
      expected.each do |name, rule|
        result = described_class.new.run([File.join(directory, name)], only: [rule]).first
        expect(result[:offenses].map(&:rule)).to include(rule), "expected #{rule} for #{name}"
      end
    end
  end

  it "checks strict expected nets and supports GitHub and SARIF output" do
    Dir.mktmpdir do |directory|
      path = File.join(directory, "strict.bk.rb")
      File.write(path, "board :mini\nresistor :R1, '330', pins: %w[a1 a3]\nresistor :R2, '220', pins: %w[b1 b6]\nexpect strict: true do\n  net :SIGNAL, 'R1.1'\nend\n")
      results = described_class.new.run([path], only: ["Intent/ConnectionMismatch"])
      expect(results.first[:offenses].first.message).to include("R2.1")
      expect(Breadkit::Lint::Formatter.new.github(results)).to include("::error file=")
      expect(JSON.parse(Breadkit::Lint::Formatter.new.sarif(results)).dig("version")).to eq("2.1.0")
    end
  end

  it "returns a fatal status for DSL evaluation errors and localizes rule descriptions" do
    Dir.mktmpdir do |directory|
      path = File.join(directory, "broken.bk.rb")
      File.write(path, "board :half\nnot valid ruby\n")
      cli = Breadkit::Lint::CLI.new
      status = nil
      expect { status = cli.run(["--format", "sarif", path]) }.to output(/2\.1\.0/).to_stdout
      expect(status).to eq(2)
      expect { status = cli.run(["--list-rules", "--locale", "ja"]) }.to output(/選択したボード/).to_stdout
      expect(status).to eq(0)
    end
  end

  it "loads custom rules through configuration" do
    Dir.mktmpdir do |directory|
      plugin = File.join(directory, "custom_rule.rb")
      config = File.join(directory, ".bklint.yml")
      File.write(plugin, <<~RUBY)
        class CustomRule < Breadkit::Lint::Rule
          rule "Custom/Marked", severity: :warning, description: "A custom check"

          def check(context)
            add_offense(context, "custom rule ran", location: nil)
          end
        end
      RUBY
      File.write(config, "require:\n  - ./custom_rule.rb\n")
      results = described_class.new(config: Breadkit::Lint::Config.new(config)).run([File.join(examples, "01_led_button.bk.rb")])
      expect(results.first[:offenses].map(&:rule)).to include("Custom/Marked")
    end
  end
end
