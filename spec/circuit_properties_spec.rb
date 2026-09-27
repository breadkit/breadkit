# frozen_string_literal: true

require "json_schemer"

RSpec.describe "circuit invariants" do
  def resolve(source)
    builder = Breadkit::DSL::Builder.new
    builder.instance_eval(source, "generated.bk.rb", 1)
    Breadkit::Resolver.new.call(builder.document)
  end

  it "round-trips randomized valid placements without changing resolved nets" do
    rng = Random.new(20_260_927)
    schema = JSONSchemer.schema(JSON.parse(File.read(File.expand_path("../schema/ir-v1.json", __dir__), encoding: "UTF-8")))
    25.times do
      rows = (2..14).to_a.sample(6, random: rng)
      lines = ["board :mini", 'supply :USB, voltage: 5, plus: "a1", minus: "a17"']
      rows.each_slice(2).with_index(1) do |(first, second), index|
        lines << %(resistor :R#{index}, "330", pins: %w[a#{first} a#{second}])
      end
      rows.take(3).zip(rows.drop(3)).each do |from, to|
        lines << %(wire "b#{from}", "f#{to}")
      end
      circuit = resolve(lines.join("\n"))
      expect(circuit.diagnostics.select { |item| item.severity == "error" }).to be_empty
      serialized = JSON.parse(JSON.generate(circuit.to_ir))
      expect(schema.valid?(serialized)).to be(true)
      restored = Breadkit::IR::Reader.new.read(serialized)
      nets = ->(item) { item.nets.map { |net| [net.name, net.members.sort] }.sort }
      expect(nets.call(restored)).to eq(nets.call(circuit))
    end
  end

  it "returns diagnostics instead of crashing on randomized invalid endpoints" do
    rng = Random.new(1_204)
    endpoints = %w[z99 a0 R99.1 T+9999 X.bad]
    25.times do
      source = %(board :mini\nwire "#{endpoints.sample(random: rng)}", "a#{rng.rand(1..17)}")
      circuit = resolve(source)
      expect(circuit.diagnostics).not_to be_empty
      expect { circuit.nets }.not_to raise_error
    end
  end
end
