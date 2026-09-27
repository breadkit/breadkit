# frozen_string_literal: true

RSpec.describe "ShillehTek MB102 four-pin power module" do
  def resolve(master: :on, left: :v3_3, right: :v5, pins: nil, selectors: true, split_rails: false)
    pins ||= { LEFT_POS: "T+1", LEFT_GND: "T-1", RIGHT_POS: "B+1", RIGHT_GND: "B-1" }
    options = selectors ? ", master: #{master.inspect}, left: #{left.inspect}, right: #{right.inspect}" : ""
    builder = Breadkit::DSL::Builder.new
    builder.instance_eval(<<~RUBY, "mb102.bk.rb", 1)
      board :full, split_rails: #{split_rails}
      part :PS1, :shillehtek_mb102_4pin, pins: #{pins.inspect}#{options}
    RUBY
    Breadkit::Resolver.new.call(builder.document)
  end

  it "loads a specifically identified four-contact variant with no assumed pin spacing" do
    part = Breadkit::PartLibrary.new.find("shillehtek_mb102_4pin")
    expect(part).not_to be_nil
    expect(part.pins.map { |pin| pin.fetch("name") }).to eq(%w[LEFT_POS LEFT_GND RIGHT_POS RIGHT_GND])
    expect(part.data["footprint"]).to be_nil
    expect(part.data["datasheet_url"]).to include("shillehtek.com")
  end

  it "powers its left and right rail pairs independently from explicitly placed pins" do
    circuit = resolve
    expect(circuit.diagnostics.select { |item| item.severity == "error" }).to be_empty
    expect(circuit.components.fetch("PS1").pins.values.map(&:hole_id)).to eq(%w[T+1 T-1 B+1 B-1])
    expect(circuit.voltage_sources.to_h { |source| [source.name, source.voltage] })
      .to eq("PS1.LEFT_POS" => 3.3, "PS1.RIGHT_POS" => 5.0)
    expect(circuit.net_of("T-1")).to eq(circuit.net_of("B-1"))
    expect(circuit.potentials.values.fetch(circuit.net_of("T+1").name) - circuit.potentials.values.fetch(circuit.net_of("T-1").name)).to eq(3.3)
    expect(circuit.potentials.values.fetch(circuit.net_of("B+1").name) - circuit.potentials.values.fetch(circuit.net_of("B-1").name)).to eq(5.0)
    expect(Breadkit::IR::Reader.new.read(circuit.to_ir).voltage_sources.map(&:voltage)).to eq([3.3, 5.0])
  end

  it "leaves a selected OFF output floating and honors the master switch" do
    left_off = resolve(left: :off)
    expect(left_off.voltage_sources.map(&:name)).to eq(["PS1.RIGHT_POS"])
    expect(left_off.net_of("T+1")).not_to eq(left_off.net_of("B+1"))
    master_off = resolve(master: :off)
    expect(master_off.voltage_sources).to be_empty
    expect(master_off.net_of("T-1")).to eq(master_off.net_of("B-1"))
  end

  it "requires explicit selector positions and rejects unknown positions" do
    unset = resolve(selectors: false)
    expect(unset.diagnostics.map(&:code)).to include("invalid_option")
    expect(unset.voltage_sources).to be_empty
    expect(resolve(left: :v12).diagnostics.map(&:code)).to include("invalid_option")
    expect(resolve(left: :v12).voltage_sources.map(&:name)).to eq(["PS1.RIGHT_POS"])
  end

  it "rejects invalid selector conditions and rail-mount metadata in part definitions" do
    original = Breadkit::PartLibrary.new.find("shillehtek_mb102_4pin").data
    invalid_condition = Marshal.load(Marshal.dump(original))
    invalid_condition.fetch("provides").first.fetch("when")["left"] = "v12"
    expect { Breadkit::PartDef.new(invalid_condition) }.to raise_error(ArgumentError, /voltage source condition/)

    invalid_required = Marshal.load(Marshal.dump(original))
    invalid_required["required_attributes"] << "unknown"
    expect { Breadkit::PartDef.new(invalid_required) }.to raise_error(ArgumentError, /required_attributes/)

    invalid_mount = Marshal.load(Marshal.dump(original))
    invalid_mount.fetch("pins").first["mount"] = "terminal"
    expect { Breadkit::PartDef.new(invalid_mount) }.to raise_error(ArgumentError, /invalid mount/)
  end

  it "rejects missing, duplicate, terminal, and reversed-polarity rail holes" do
    base = { LEFT_POS: "T+1", LEFT_GND: "T-1", RIGHT_POS: "B+1", RIGHT_GND: "B-1" }
    expect(resolve(pins: base.except(:RIGHT_GND)).diagnostics.map(&:code)).to include("unplaced_pin")
    expect(resolve(pins: base.merge(RIGHT_POS: "T+1")).diagnostics.map(&:code)).to include("hole_conflict")
    expect(resolve(pins: base.merge(LEFT_POS: "a1")).diagnostics.map(&:code)).to include("invalid_placement")
    expect(resolve(pins: base.merge(LEFT_POS: "T-2")).diagnostics.map(&:code)).to include("invalid_placement")
  end

  it "does not energize the far half of an unbridged split rail" do
    circuit = resolve(split_rails: true)
    expect(circuit.net_of("T+30")).not_to eq(circuit.net_of("T+1"))
  end
end
