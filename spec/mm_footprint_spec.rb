# frozen_string_literal: true

require "json_schemer"

RSpec.describe "millimeter footprint offsets" do
  let(:definition) do
    { "id" => "test_mm_footprint", "placement" => "footprint", "straddle" => true,
      "pins" => (1..4).map { |number| { "num" => number } },
      "footprint_mm" => { "1" => [0, 0], "2" => [5.08, 0], "3" => [0, 7.62], "4" => [5.08, 7.62] } }
  end

  it "snaps physical offsets to the 2.54 mm hole pitch and places across the gap" do
    definition_part = Breadkit::PartDef.new(definition)
    expect(definition_part.footprint).to eq({ "1" => [0, 0], "2" => [2, 0], "3" => [0, 3], "4" => [2, 3] })
    schema = JSONSchemer.schema(JSON.parse(File.read(File.expand_path("../schema/part-v1.json", __dir__))))
    expect(schema.valid?(definition_part.data)).to be(true)

    builder = Breadkit::DSL::Builder.new
    builder.document.part_definitions << definition
    builder.instance_eval('board :full; part :J1, :test_mm_footprint, at: "e10"', "mm.bk.rb", 1)
    circuit = Breadkit::Resolver.new.call(builder.document)
    expect(circuit.diagnostics.select { |item| item.severity == "error" }).to be_empty
    expect(circuit.components.fetch("J1").pins.transform_values(&:hole_id))
      .to eq({ "1" => "e10", "2" => "e12", "3" => "f10", "4" => "f12" })
    expect(Breadkit::IR::Reader.new.read(circuit.to_ir).to_ir).to eq(circuit.to_ir)
  end

  it "rejects offsets that cannot occupy the declared breadboard grid" do
    bad = definition.merge("footprint_mm" => { "1" => [0, 0], "2" => [2.5, 0] })
    expect { Breadkit::PartDef.new(bad) }.to raise_error(ArgumentError, /footprint_mm/)
    both = definition.merge("footprint" => { "1" => [0, 0] })
    expect { Breadkit::PartDef.new(both) }.to raise_error(ArgumentError, /footprint_mm.*footprint/)
    unknown = definition.merge("footprint_mm" => { "5" => [0, 0] })
    expect { Breadkit::PartDef.new(unknown) }.to raise_error(ArgumentError, /footprint_mm/)
  end
end
