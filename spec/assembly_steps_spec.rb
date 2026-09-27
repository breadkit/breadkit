# frozen_string_literal: true

require "json_schemer"

RSpec.describe "assembly steps" do
  let(:source) do
    <<~RUBY
      board :mini
      step 1, title: "Install the supply and resistor" do
        supply :USB, voltage: 5, plus: "a1", minus: "a2"
        net :VCC, at: "a1"
        resistor :R1, "330", pins: %w[b1 b3]
      end
      step 2, title: "Add the LED and return wire" do
        led :D1, color: :red, anode: "c3", cathode: "c4"
        wire "d4", "b2", color: :black
      end
    RUBY
  end

  it "records numbered declarations and round-trips them through schema-valid IR" do
    builder = Breadkit::DSL::Builder.new
    builder.instance_eval(source, "steps.bk.rb", 1)
    circuit = Breadkit::Resolver.new.call(builder.document)
    expect(circuit.diagnostics).to be_empty
    expect(circuit.steps.map { |step| step[:number] }).to eq([1, 2])
    expect(circuit.steps.map { |step| step[:title] }).to eq(["Install the supply and resistor", "Add the LED and return wire"])
    expect(circuit.supplies.first.step).to eq(1)
    expect(circuit.labels.first.step).to eq(1)
    expect(circuit.components.fetch("R1").step).to eq(1)
    expect(circuit.components.fetch("D1").step).to eq(2)
    expect(circuit.wires.first.step).to eq(2)

    ir = circuit.to_ir
    schema = JSONSchemer.schema(JSON.parse(File.read(File.expand_path("../schema/ir-v1.json", __dir__))))
    expect(schema.valid?(ir)).to be(true)
    expect(ir.fetch(:steps).map { |step| step.fetch(:number) }).to eq([1, 2])
    expect(Breadkit::IR::Reader.new.read(ir).to_ir).to eq(ir)
  end

  it "rejects missing, out-of-order, nested, and invalid step declarations" do
    builder = Breadkit::DSL::Builder.new
    expect { builder.instance_eval('step 2 do resistor :R1, "330", pins: %w[a1 a3] end', "steps.bk.rb", 1) }
      .to raise_error(Breadkit::DSLError, /step number must be 1/)
    expect { builder.instance_eval('step 1', "steps.bk.rb", 1) }
      .to raise_error(Breadkit::DSLError, /requires a body/)
    expect { builder.instance_eval('step 1, title: "" do end', "steps.bk.rb", 1) }
      .to raise_error(Breadkit::DSLError, /title must be nonempty text/)
    expect { builder.instance_eval('step 1 do step 2 do end end', "steps.bk.rb", 1) }
      .to raise_error(Breadkit::DSLError, /nested step/)
  end

  it "rejects inconsistent step metadata when reading IR" do
    builder = Breadkit::DSL::Builder.new
    builder.instance_eval(source, "steps.bk.rb", 1)
    ir = Breadkit::Resolver.new.call(builder.document).to_ir
    ir[:components].first[:step] = 3
    expect { Breadkit::IR::Reader.new.read(ir) }.to raise_error(Breadkit::DSLError, /components\[0\]\.step/)
    ir[:components].first[:step] = 1
    ir[:steps].last[:number] = 4
    expect { Breadkit::IR::Reader.new.read(ir) }.to raise_error(Breadkit::DSLError, /steps\[1\]\.number/)
  end

  it "keeps IR without assembly steps unchanged" do
    builder = Breadkit::DSL::Builder.new
    builder.instance_eval('board :mini; resistor :R1, "330", pins: %w[a1 a3]', "plain.bk.rb", 1)
    ir = Breadkit::Resolver.new.call(builder.document).to_ir
    expect(ir).not_to have_key(:steps)
    expect(ir.fetch(:components).first).not_to have_key(:step)
    expect(Breadkit::IR::Reader.new.read(ir).to_ir).to eq(ir)
  end
end
