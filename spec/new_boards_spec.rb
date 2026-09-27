# frozen_string_literal: true

RSpec.describe "isolated and row-strip boards" do
  it "publishes schema-valid board definitions" do
    schema = JSONSchemer.schema(JSON.parse(File.read(File.expand_path("../schema/board-v1.json", __dir__))))
    %w[universal stripboard].each do |name|
      expect(schema.valid?(Breadkit::BoardDef.load(name).data)).to be(true), name
    end
  end

  it "keeps universal pads isolated and connects each stripboard row" do
    universal = Breadkit::Board.new(Breadkit::BoardDef.load("universal"))
    expect(universal.strip("a1")).to eq(["a1"])
    expect(universal.strip("a2")).to eq(["a2"])
    stripboard = Breadkit::Board.new(Breadkit::BoardDef.load("stripboard"))
    expect(stripboard.strip("a1")).to include("a1", "a2")
    expect(stripboard.strip("a1")).not_to include("b1")
    expect(stripboard.strip("b1")).to include("b2")
  end

  it "preserves row strips across IR round trips and named boards" do
    source = 'board :stripboard, as: :B1; board :universal, as: :B2; wire "B1.a1", "B2.a1"'
    document = Breadkit::DSL.load_file("boards.bk.rb", source: source)
    circuit = Breadkit::Resolver.new.call(document)
    expect(circuit.net_of("B1.a2")).to eq(circuit.net_of("B2.a1"))
    expect(circuit.net_of("B2.a2")).not_to eq(circuit.net_of("B2.a1"))
    restored = Breadkit::IR::Reader.new.read(circuit.to_ir)
    expect(restored.net_of("B1.a2")).to eq(restored.net_of("B2.a1"))
    expect(restored.net_of("B2.a2")).not_to eq(restored.net_of("B2.a1"))
    schema = JSONSchemer.schema(JSON.parse(File.read(File.expand_path("../schema/ir-v2.json", __dir__))))
    expect(schema.valid?(JSON.parse(JSON.generate(circuit.to_ir)))).to be(true)
  end

  it "rejects unknown terminal strip directions" do
    data = Breadkit::BoardDef.load("mini").data
    invalid = data.merge("terminal" => data.fetch("terminal").merge("strip_direction" => "diagonal"))
    expect { Breadkit::BoardDef.new(invalid) }.to raise_error(ArgumentError, /strip_direction/)
    rows = data.fetch("terminal").fetch("rows")
    grouped = data.merge("terminal" => data.fetch("terminal").merge("strip_direction" => "row", "groups" => [%w[a b]] + rows.drop(2).map { |row| [row] }))
    expect { Breadkit::BoardDef.new(grouped) }.to raise_error(ArgumentError, /one terminal row/)
  end
end
