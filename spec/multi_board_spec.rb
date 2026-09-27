# frozen_string_literal: true

require "json_schemer"
require "tmpdir"

RSpec.describe "named breadboards" do
  def circuit(source)
    builder = Breadkit::DSL::Builder.new
    builder.instance_eval(source, "boards.bk.rb", 1)
    Breadkit::Resolver.new.call(builder.document)
  end

  it "keeps strips separate until a cross-board wire connects them" do
    result = circuit(<<~RUBY)
      board :half, as: :B1
      board :mini, as: :B2
      resistor :R1, "330", pins: %w[B1.a1 B1.a3]
      resistor :R2, "330", pins: %w[B2.a1 B2.a3]
      wire "B1.b1", "B2.b1"
    RUBY
    expect(result.diagnostics).to be_empty
    expect(result.board.hole("B1.a1").strip_id).not_to eq(result.board.hole("B2.a1").strip_id)
    expect(result.net_of("R1.1")).to eq(result.net_of("R2.1"))
    expect(result.net_of("R1.2")).not_to eq(result.net_of("R2.2"))
    expect(result.shortest_path("B1.a1", "B2.a1")).to include("W1")
    expect(result.boards.keys).to eq(%w[B1 B2])
  end

  it "resolves footprints on their own boards and rejects a component spanning boards" do
    result = circuit(<<~RUBY)
      board :half, as: :B1
      board :mini, as: :B2
      ic :U1, "NE555", at: "B1.e20"
      ic :U2, "NE555", at: "B2.e5"
    RUBY
    expect(result.diagnostics).to be_empty
    expect(result.components.fetch("U1").pin("VCC").hole_id).to eq("B1.f20")
    expect(result.components.fetch("U2").pin("VCC").hole_id).to eq("B2.f5")

    invalid = circuit('board :mini, as: :B1; board :mini, as: :B2; resistor :R1, "330", pins: %w[B1.a1 B2.a3]')
    expect(invalid.diagnostics.map(&:code)).to include("invalid_placement")
  end

  it "rejects ambiguous unqualified holes and mixed board declarations" do
    result = circuit('board :mini, as: :B1; board :mini, as: :B2; wire "a1", "B2.b1"')
    expect(result.diagnostics.map(&:code)).to include("invalid_hole")
    expect(result.board.hole("a1")).to be_nil
    builder = Breadkit::DSL::Builder.new
    expect { builder.instance_eval('board :mini; board :mini, as: :B2', "boards.bk.rb", 1) }
      .to raise_error(Breadkit::DSLError, /named and unnamed boards/)
    builder = Breadkit::DSL::Builder.new
    expect { builder.instance_eval('board :mini, as: :B1; board :mini, as: :B1', "boards.bk.rb", 1) }
      .to raise_error(Breadkit::DSLError, /duplicate board name/)
  end

  it "round-trips named boards in v2 IR while leaving single-board IR at v1" do
    result = circuit('board :half, as: :B1; board :mini, as: :B2; wire "B1.a1", "B2.j1"')
    expect(result.diagnostics).to be_empty
    ir = result.to_ir
    expect(ir.fetch(:schema_version)).to eq(2)
    expect(ir.fetch(:boards).map { |board| board.fetch(:name) }).to eq(%w[B1 B2])
    schema = JSONSchemer.schema(JSON.parse(File.read(File.expand_path("../schema/ir-v2.json", __dir__))))
    serialized = JSON.parse(JSON.generate(ir))
    expect(schema.validate(serialized).to_a).to be_empty
    expect(Breadkit::IR::Reader.new.read(serialized).to_ir).to eq(ir)

    single = circuit('board :mini; wire "a1", "b2"').to_ir
    expect(single.fetch(:schema_version)).to eq(1)
    expect(single).not_to have_key(:boards)
  end

  it "keeps automatic rail selection on the named target board" do
    result = circuit('board :half, as: :B1; board :half, as: :B2; wire "B1.a10", "B2.T+"')
    expect(result.diagnostics).to be_empty
    expect(result.wires.first.to).to start_with("B2.T+")
    expect(result.board.hole(result.wires.first.to).rail).to eq("B2.T+")
  end

  it "resolves a powered cross-board path without merging unrelated strips" do
    result = circuit(<<~RUBY)
      board :mini, as: :B1
      board :mini, as: :B2
      supply :BAT, voltage: 5, plus: "B1.a1", minus: "B2.b5"
      resistor :R1, "330", pins: %w[B1.b1 B1.a3]
      led :D1, anode: "B2.a3", cathode: "B2.a5"
      wire "B1.b3", "B2.b3"
    RUBY
    expect(result.diagnostics).to be_empty
    expect(result.net_of("BAT.+")).to eq(result.net_of("R1.1"))
    expect(result.net_of("R1.2")).to eq(result.net_of("D1.A"))
    expect(result.net_of("BAT.-")).to eq(result.net_of("D1.K"))
    expect(result.net_of("B1.a5")).not_to eq(result.net_of("BAT.-"))
    expect(result.potentials.values.fetch(result.net_of("BAT.+").name)).to eq(5.0)
  end

  it "rejects invalid or lossy v2 board records" do
    ir = circuit('board :mini, as: :B1; board :mini, as: :B2').to_ir
    ir[:boards].last[:name] = "b1"
    expect { Breadkit::IR::Reader.new.read(ir) }.to raise_error(Breadkit::DSLError, /duplicate board name/)
    ir[:boards].last[:name] = "B2"
    ir[:boards].last[:definition] = ir[:boards].last[:definition].merge("id" => "half")
    expect { Breadkit::IR::Reader.new.read(ir) }.to raise_error(Breadkit::DSLError, /definition.id must match type/)
    ir[:boards].last[:definition] = ir[:boards].first[:definition]
    ir[:board] = { type: "mini" }
    expect { Breadkit::IR::Reader.new.read(ir) }.to raise_error(Breadkit::DSLError, /v2 must use boards/)
  end

  it "rejects malformed embedded boards instead of replacing their geometry" do
    ir = circuit('board :mini, as: :B1; board :mini, as: :B2').to_ir
    ir[:boards].last[:definition] = Marshal.load(Marshal.dump(ir[:boards].last[:definition]))
    ir[:boards].last[:definition]["rails"] = ["invalid"]
    expect { Breadkit::IR::Reader.new.read(ir) }.to raise_error(Breadkit::DSLError, /boards\[1\]\.definition/)
  end

  it "rejects duplicate board names in a document before they can overwrite a board" do
    document = Breadkit::Document.new
    document.boards = [{ name: "B1", type: "half", options: {} }, { name: "b1", type: "mini", options: {} }]
    expect { Breadkit::Resolver.new.call(document) }.to raise_error(Breadkit::DSLError, /duplicate board name/)
  end

  it "loads named boards from declarative YAML and TOML" do
    Dir.mktmpdir do |dir|
      yaml = File.join(dir, "boards.bk.yml")
      toml = File.join(dir, "boards.bk.toml")
      File.write(yaml, <<~YAML)
        boards:
          - {name: B1, type: half}
          - {name: B2, type: mini}
        wires:
          - {from: B1.a1, to: B2.j1}
      YAML
      File.write(toml, <<~TOML)
        [[boards]]
        name = "B1"
        type = "half"
        [[boards]]
        name = "B2"
        type = "mini"
        [[wires]]
        from = "B1.a1"
        to = "B2.j1"
      TOML
      [yaml, toml].each do |path|
        result = Breadkit.load(path)
        expect(result.diagnostics).to be_empty
        expect(result.boards.keys).to eq(%w[B1 B2])
        expect(result.wires.first.from).to eq("B1.a1")
        expect(result.to_ir.fetch(:schema_version)).to eq(2)
      end
    end
  end
end
