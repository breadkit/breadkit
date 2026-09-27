# frozen_string_literal: true

require "json_schemer"

RSpec.describe "part datasheet URLs" do
  let(:definition) { { "id" => "sensor", "placement" => "offboard", "pins" => [{ "num" => 1 }] } }

  it "accepts an HTTPS datasheet URL and rejects malformed or unsafe links" do
    part = Breadkit::PartDef.new(definition.merge("datasheet_url" => "https://example.com/sensor.pdf"))
    expect(part.data.fetch("datasheet_url")).to eq("https://example.com/sensor.pdf")
    schema = JSONSchemer.schema(JSON.parse(File.read(File.expand_path("../schema/part-v1.json", __dir__))))
    expect(schema.valid?(part.data)).to be(true)

    ["http://example.com/sensor.pdf", "javascript:alert(1)", "https://", "https://user@example.com/x.pdf", 42].each do |url|
      expect { Breadkit::PartDef.new(definition.merge("datasheet_url" => url)) }
        .to raise_error(ArgumentError, /datasheet_url/)
    end
  end

  it "round-trips a custom datasheet URL in both IR versions" do
    [false, true].each do |named|
      builder = Breadkit::DSL::Builder.new
      builder.document.part_definitions << definition.merge("datasheet_url" => "https://example.com/sensor.pdf")
      boards = named ? 'board :mini, as: :B1; board :mini, as: :B2' : 'board :mini'
      builder.instance_eval("#{boards}; offboard :S1, :sensor", "datasheet.bk.rb", 1)
      ir = Breadkit::Resolver.new.call(builder.document).to_ir
      schema = JSONSchemer.schema(JSON.parse(File.read(File.expand_path("../schema/ir-v#{named ? 2 : 1}.json", __dir__))))
      expect(schema.valid?(ir)).to be(true)
      expect(ir.fetch(:part_definitions).first.fetch("datasheet_url")).to eq("https://example.com/sensor.pdf")
      expect(Breadkit::IR::Reader.new.read(ir).to_ir).to eq(ir)
    end
  end
end
