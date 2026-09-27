# frozen_string_literal: true

require "json_schemer"

RSpec.describe "per-pin current limits" do
  let(:definition) do
    { "id" => "gpio_test", "placement" => "offboard",
      "pins" => [{ "num" => 1, "name" => "OUT", "type" => "gpio", "max_current" => 0.012 },
                 { "num" => 2, "name" => "GND", "type" => "ground" }] }
  end

  it "accepts a finite positive current limit in amperes on a pin" do
    part = Breadkit::PartDef.new(definition)
    expect(part.pin("OUT").fetch("max_current")).to eq(0.012)
    expect(part.pin("GND")).not_to have_key("max_current")
    schema = JSONSchemer.schema(JSON.parse(File.read(File.expand_path("../schema/part-v1.json", __dir__))))
    expect(schema.valid?(part.data)).to be(true)
  end

  it "rejects invalid limits on any pin type" do
    [0, -1, Float::INFINITY, Float::NAN, "12mA", true, Complex(1, 1)].each do |value|
      invalid = definition.merge("pins" => [{ "num" => 1, "max_current" => value }])
      expect { Breadkit::PartDef.new(invalid) }.to raise_error(ArgumentError, /max_current/)
    end
  end

  it "preserves custom pin limits through schema-valid v1 and v2 IR" do
    [false, true].each do |named|
      builder = Breadkit::DSL::Builder.new
      builder.document.part_definitions << definition
      boards = named ? 'board :mini, as: :B1; board :mini, as: :B2' : 'board :mini'
      builder.instance_eval("#{boards}; offboard :U1, :gpio_test", "current.bk.rb", 1)
      ir = Breadkit::Resolver.new.call(builder.document).to_ir
      version = named ? 2 : 1
      schema = JSONSchemer.schema(JSON.parse(File.read(File.expand_path("../schema/ir-v#{version}.json", __dir__))))
      expect(schema.valid?(ir)).to be(true)
      expect(ir.fetch(:part_definitions).first.fetch("pins").first.fetch("max_current")).to eq(0.012)
      restored = Breadkit::IR::Reader.new.read(ir)
      expect(restored.components.fetch("U1").part.pin("OUT").fetch("max_current")).to eq(0.012)
      expect(restored.to_ir).to eq(ir)
    end
  end
end
