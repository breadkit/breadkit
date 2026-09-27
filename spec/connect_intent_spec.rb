# frozen_string_literal: true

require "tmpdir"
require "json_schemer"

RSpec.describe "layout-independent connection intent" do
  def resolve(source)
    Breadkit::Resolver.new.call(Breadkit::DSL.load_file("intent.bk.rb", source: source))
  end

  it "declares an expected connection before placing parts without adding a wire" do
    source = <<~RUBY
      connect "R1.1", "R2.1"
      board :mini
      resistor :R1, "330", pins: %w[a1 a2]
      resistor :R2, "1k", pins: %w[b3 b4]
    RUBY
    circuit = resolve(source)
    expect(circuit.diagnostics).to be_empty
    expect(circuit.wires).to be_empty
    expect(circuit.net_of("R1.1")).not_to eq(circuit.net_of("R2.1"))
    entry = circuit.expectations.first.fetch(:entries).first
    expect(entry).to include(kind: "connected", refs: %w[R1.1 R2.1])
    restored = Breadkit::IR::Reader.new.read(circuit.to_ir)
    expect(restored.expectations.first.fetch("entries").first).to include("kind" => "connected", "refs" => %w[R1.1 R2.1])
    schema = JSONSchemer.schema(JSON.parse(File.read(File.expand_path("../schema/ir-v1.json", __dir__))))
    expect(schema.valid?(JSON.parse(JSON.generate(circuit.to_ir)))).to be(true)
  end

  it "keeps state-specific intent and diagnoses unknown pin references" do
    source = <<~RUBY
      connect "MISSING.1", "R1.1", when: "SW1"
      board :mini
      resistor :R1, "330", pins: %w[a1 a2]
    RUBY
    circuit = resolve(source)
    expect(circuit.expectations.first.fetch(:when)).to eq("SW1")
    expect(circuit.diagnostics.map(&:code)).to include("unknown_pin")
    expect(circuit.diagnostics.find { |item| item.code == "unknown_pin" }.targets).to include("MISSING.1")
  end

  it "accepts equivalent YAML and TOML intent declarations" do
    Dir.mktmpdir do |dir|
      yaml = File.join(dir, "intent.bk.yml")
      toml = File.join(dir, "intent.bk.toml")
      File.write(yaml, "board: mini\nconnections:\n  - {from: R1.1, to: R2.1}\nparts:\n  - {ref: R1, type: resistor, value: '330', pins: [a1, a2]}\n  - {ref: R2, type: resistor, value: '1k', pins: [b3, b4]}\n")
      File.write(toml, "board = 'mini'\n[[connections]]\nfrom = 'R1.1'\nto = 'R2.1'\n[[parts]]\nref = 'R1'\ntype = 'resistor'\nvalue = '330'\npins = ['a1', 'a2']\n[[parts]]\nref = 'R2'\ntype = 'resistor'\nvalue = '1k'\npins = ['b3', 'b4']\n")
      [yaml, toml].each do |path|
        circuit = Breadkit.load(path)
        expect(circuit.diagnostics).to be_empty
        expect(circuit.wires).to be_empty
        expect(circuit.expectations.first.fetch(:entries).first).to include(kind: "connected", refs: %w[R1.1 R2.1])
      end
    end
  end

  it "rejects incomplete intent instead of silently making a partial assertion" do
    expect { Breadkit::DSL.load_file("intent.bk.rb", source: 'connect "R1.1"') }
      .to raise_error(Breadkit::DSLError, /exactly two/)
    expect { Breadkit::DSL.load_file("intent.bk.rb", source: 'connect "R1.1", "R2.1", color: :red') }
      .to raise_error(Breadkit::DSLError, /unknown connect option/)
  end
end
