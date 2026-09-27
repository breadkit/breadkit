# frozen_string_literal: true

RSpec.describe "Fritzing sketch export" do
  def circuit(source)
    builder = Breadkit::DSL::Builder.new
    builder.instance_eval(source, "fritzing.bk.rb", 1)
    Breadkit::Resolver.new.call(builder.document)
  end

  it "maps all four 830-hole breadboard rails and emits reciprocal jumper links" do
    input = circuit('board :full; wire "a1", "T+1", color: :red; wire "B-6", "j63", color: :black; wire "a2", "T-50"; wire "B+50", "j62"')
    output = Breadkit::Exporters.call(input, format: "fritzing")
    expect(output).to include('<module fritzingVersion=',
                              'moduleIdRef="Breadboard-RSR03MB102-ModuleID"',
                              'connectorId="pin1A"', 'connectorId="pin3Y"',
                              'connectorId="pin9X"', 'connectorId="pin63J"',
                              'connectorId="pin61Z"', 'connectorId="pin61W"',
                              'moduleIdRef="WireModuleID"', 'wireFlags="64"')
    expect(output.scan('connectorId="pin1A"').length).to eq(6)
    expect(output.scan('connectorId="pin3Y"').length).to eq(6)
    expect(output.scan('moduleIdRef="WireModuleID"').length).to eq(4)
  end

  it "rejects circuits it cannot represent faithfully" do
    half = circuit('board :half; wire "a1", "a2"')
    component = circuit('board :full; resistor :R1, "1k", pins: %w[a1 a3]')
    routed = circuit('board :full; wire "a1", "a3", route: :arc')
    expect { Breadkit::Exporters.call(half, format: "fritzing") }.to raise_error(ArgumentError, /full.*board/)
    expect { Breadkit::Exporters.call(component, format: "fritzing") }.to raise_error(ArgumentError, /unsupported part R1/)
    expect { Breadkit::Exporters.call(routed, format: "fritzing") }.to raise_error(ArgumentError, /straight/)
  end

  it "exports through the CLI as uncompressed Fritzing XML" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "simple.bk.rb")
      File.write(path, 'board :full; wire "a1", "a3"')
      expect { expect(Breadkit::CLI.new.run(["export", "--format", "fritzing", path])).to eq(0) }
        .to output(/Breadboard-RSR03MB102-ModuleID/).to_stdout
    end
  end
end
