# frozen_string_literal: true

require "json_schemer"

RSpec.describe "Part SVG metadata" do
  let(:schema) do
    JSONSchemer.schema(JSON.parse(File.read(File.expand_path("../schema/part-v1.json", __dir__), encoding: "UTF-8")))
  end

  it "accepts an SVG template string without interpreting it in core" do
    data = { "id" => "custom", "pins" => [{ "num" => 1 }], "render" => { "svg" => '<svg viewBox="0 0 10 10"/>' } }
    expect(Breadkit::PartDef.new(data).data.dig("render", "svg")).to eq(data.dig("render", "svg"))
    expect(schema.valid?(data)).to be(true)
  end

  it "rejects a non-string SVG template" do
    data = { "id" => "custom", "pins" => [{ "num" => 1 }], "render" => { "svg" => 123 } }
    expect { Breadkit::PartDef.new(data) }.to raise_error(ArgumentError, /invalid render options/)
    expect(schema.valid?(data)).to be(false)
  end
end
