# frozen_string_literal: true

RSpec.describe "Independent switch positions" do
  def circuit(source)
    builder = Breadkit::DSL::Builder.new
    builder.instance_eval(source, "dip-switch.bk.rb", 1)
    Breadkit::Resolver.new.call(builder.document)
  end

  it "closes each BD04 position without closing its neighbors" do
    resolved = circuit('board :full; part :SW1, :ck_bd04, at: "e20"')
    expect(resolved.diagnostics).to be_empty
    expect(resolved.components.fetch("SW1").pins.transform_values(&:hole_id)).to eq(
      "P1A" => "e20", "P1B" => "f20", "P2A" => "e21", "P2B" => "f21",
      "P3A" => "e22", "P3B" => "f22", "P4A" => "e23", "P4B" => "f23"
    )
    expect(resolved.states("single").map(&:name)).to eq([nil, "SW1.1", "SW1.2", "SW1.3", "SW1.4"])
    selected = resolved.state("SW1.2")
    expect(resolved.net_of("SW1.P2A", selected)).to eq(resolved.net_of("SW1.P2B", selected))
    expect(resolved.net_of("SW1.P1A", selected)).not_to eq(resolved.net_of("SW1.P1B", selected))
    expect(resolved.net_of("SW1.P3A", selected)).not_to eq(resolved.net_of("SW1.P3B", selected))
    restored = Breadkit::IR::Reader.new.read(resolved.to_ir)
    expect(restored.net_of("SW1.P2A", restored.state("SW1.2"))).to eq(restored.net_of("SW1.P2B", restored.state("SW1.2")))
  end

  it "supports all sixteen combinations and explicit combined states" do
    resolved = circuit('board :full; part :SW1, :ck_bd04, at: "e20"')
    expect(resolved.states("all", budget: 16).length).to eq(16)
    expect { resolved.states("all", budget: 15) }.to raise_error(ArgumentError, /16.*budget.*15/)
    state = resolved.state("SW1.1,SW1.4")
    expect(state.closed_switches.map(&:last)).to eq([%w[P1A P1B], %w[P4A P4B]])
    expect { resolved.state("SW1") }.to raise_error(ArgumentError, /unknown switch state/)
    expect { resolved.state("SW1.1,SW1.1") }.to raise_error(ArgumentError, /unknown switch state/)
  end

  it "rejects independent switch definitions with overlapping contacts" do
    data = { "id" => "bad_dip", "placement" => "offboard", "pins" => (1..3).map { |n| { "num" => n } },
             "switch" => [[1, 2], [2, 3]], "independent_switches" => true }
    expect { Breadkit::PartDef.new(data) }.to raise_error(ArgumentError, /independent_switches/)
    expect { Breadkit::PartDef.new(data.merge("independent_switches" => "yes")) }.to raise_error(ArgumentError, /independent_switches/)
  end

  it "selects a single BD04 position through the CLI" do
    require "tempfile"
    Tempfile.create(["dip-switch", ".bk.rb"]) do |file|
      file.write('board :full; part :SW1, :ck_bd04, at: "e20"')
      file.flush
      expect { expect(Breadkit::CLI.new.run(["nets", "--state", "SW1.2", file.path])).to eq(0) }
        .to output(/SW1\.P2A.*SW1\.P2B/).to_stdout
    end
  end
end
