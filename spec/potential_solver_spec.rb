# frozen_string_literal: true

require "tmpdir"

RSpec.describe "potential solver and supply validation" do
  def circuit(source, path: "example.bk.rb")
    Breadkit::Resolver.new.call(Breadkit::DSL.load_file(path, source: source))
  end

  it "reports distinct conflicting terminal pairs from the same supplies" do
    result = circuit('board :mini; supply :A, voltage: 5, plus: "a1", minus: "a2"; supply :B, voltage: 3.3, plus: "b1", minus: "b2"')
      .potentials
    pairs = result.conflicts.map { |item| [item[:terminal_a], item[:terminal_b]].sort }
    expect(pairs).to contain_exactly(%w[A.+ B.+], %w[A.- B.-])

    direct_short = circuit('board :mini; supply :USB, voltage: 5, plus: "a1", minus: "b1"')
    expect(direct_short.potentials.conflicts.map { |item| [item[:terminal_a], item[:terminal_b]].sort })
      .to eq([%w[USB.+ USB.-]])
  end

  it "grounds standard aliases case-insensitively and accepts custom board aliases" do
    %w[gnd 0V VSS GROUND].each do |name|
      resolved = circuit("board :mini; supply :USB, voltage: 5, plus: 'a1', minus: 'a2'; net #{name.inspect}, at: 'a1'")
      expect(resolved.potentials.values.fetch(name)).to eq(0.0)
      expect(resolved.net_of("a2").potential).to eq(-5.0)
    end

    Dir.mktmpdir do |dir|
      board_file = File.join(dir, "custom.yml")
      definition = Breadkit::BoardDef.load("mini").data.merge("id" => "custom", "ground_labels" => ["RETURN"])
      File.write(board_file, YAML.dump(definition))
      source = "use_boards #{board_file.inspect}; board :custom; supply :USB, voltage: 5, plus: 'a1', minus: 'a2'; net :RETURN, at: 'a1'"
      resolved = circuit(source, path: File.join(dir, "circuit.bk.rb"))
      expect(resolved.potentials.values.fetch("RETURN")).to eq(0.0)
      expect(resolved.net_of("a2").potential).to eq(-5.0)
    end
  end

  it "rejects zero or negative standalone supplies and voltage ranges" do
    builder = Breadkit::DSL::Builder.new
    [0, -5, (0..5), (-5..-1)].each do |voltage|
      expect { builder.supply(:BAD, voltage: voltage, plus: "a1", minus: "a2") }
        .to raise_error(Breadkit::DSLError, /positive/)
    end
  end

end
