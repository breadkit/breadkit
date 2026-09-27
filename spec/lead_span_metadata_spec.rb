# frozen_string_literal: true

require "json_schemer"

RSpec.describe "lead span metadata" do
  let(:definition) do
    { "id" => "axial_test", "placement" => "leads",
      "pins" => [{ "num" => 1, "name" => "A" }, { "num" => 2, "name" => "B" }] }
  end

  it "accepts a positive physical span for a two-pin lead part" do
    part = Breadkit::PartDef.new(definition.merge("max_lead_span_mm" => 20.0))
    expect(part.max_lead_span_mm).to eq(20.0)
    schema = JSONSchemer.schema(JSON.parse(File.read(File.expand_path("../schema/part-v1.json", __dir__))))
    expect(schema.valid?(part.data)).to be(true)
    expect(Breadkit::PartDef.new(definition).max_lead_span_mm).to be_nil
  end

  it "rejects invalid limits and parts without exactly two free leads" do
    [0, -1, Float::INFINITY, Float::NAN, "20"].each do |value|
      expect { Breadkit::PartDef.new(definition.merge("max_lead_span_mm" => value)) }
        .to raise_error(ArgumentError, /max_lead_span_mm/)
    end
    three_pin = definition.merge("pins" => definition.fetch("pins") + [{ "num" => 3 }])
    expect { Breadkit::PartDef.new(three_pin.merge("max_lead_span_mm" => 20)) }
      .to raise_error(ArgumentError, /max_lead_span_mm/)
    footprint = definition.merge("placement" => "footprint", "max_lead_span_mm" => 20)
    expect { Breadkit::PartDef.new(footprint) }.to raise_error(ArgumentError, /max_lead_span_mm/)
  end

  it "preserves custom lead limits in schema-valid IR" do
    builder = Breadkit::DSL::Builder.new
    builder.document.part_definitions << definition.merge("max_lead_span_mm" => 20)
    builder.instance_eval('board :mini; part :X1, :axial_test, pins: %w[a1 a3]', "span.bk.rb", 1)
    ir = Breadkit::Resolver.new.call(builder.document).to_ir
    schema = JSONSchemer.schema(JSON.parse(File.read(File.expand_path("../schema/ir-v1.json", __dir__))))
    expect(schema.valid?(ir)).to be(true)
    expect(ir.fetch(:part_definitions).first.fetch("max_lead_span_mm")).to eq(20)
    expect(Breadkit::IR::Reader.new.read(ir).to_ir).to eq(ir)
  end
end
