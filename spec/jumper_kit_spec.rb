# frozen_string_literal: true

require "stringio"
require "tmpdir"

RSpec.describe "jumper kit allocation" do
  def circuit(source)
    Breadkit::Resolver.new.call(Breadkit::DSL.load_file("kit.bk.rb", source: source))
  end

  it "uses measured usable spans and inventory counts for straight terminal wires" do
    resolved = circuit('board :mini; wire "a1", "a3", color: :red; wire "a5", "a10", color: :red')
    inventory = { "wires" => [{ "color" => "red", "usable_span_mm" => 6, "count" => 1 },
                              { "color" => "red", "usable_span_mm" => 13, "count" => 1 }] }
    result = Breadkit::JumperKit.new(inventory).allocate(resolved)
    expect(result[:assignments].map { |item| [item[:wire], item[:usable_span_mm], item[:minimum_span_mm]] })
      .to eq([["W1", 6.0, 5.08], ["W2", 13.0, 12.7]])
    expect(result[:unassigned]).to be_empty
    expect(result[:skipped]).to be_empty
    expect(resolved.wires.length).to eq(2)
  end

  it "reserves a scarce color for a wire that requires it" do
    resolved = circuit('board :mini; wire "a1", "a3"; wire "a5", "a7", color: :red')
    inventory = { "wires" => [{ "color" => "blue", "usable_span_mm" => 6, "count" => 1 },
                              { "color" => "red", "usable_span_mm" => 6, "count" => 1 }] }
    result = Breadkit::JumperKit.new(inventory).allocate(resolved)
    expect(result[:assignments].map { |item| [item[:wire], item[:color]] }).to eq([%w[W1 blue], %w[W2 red]])
  end

  it "reports unavailable and geometrically unsupported wires without inventing a fit" do
    resolved = circuit('board :half; wire "a1", "a10", color: :red; wire "a2", "a3", route: :arc; wire "B+1", "a4"; wire "a5", "a6", electrical: false')
    result = Breadkit::JumperKit.new({ "wires" => [{ "color" => "red", "usable_span_mm" => 6, "count" => 1 }] }).allocate(resolved)
    expect(result[:assignments]).to be_empty
    expect(result[:unassigned]).to eq([{ wire: "W1", reason: "no compatible jumper in inventory" }])
    expect(result[:skipped].map { |item| item[:wire] }).to eq(%w[W2 W3 W4])
  end

  it "skips cross-board distances because named-board spacing is display-only" do
    resolved = circuit('board :mini, as: :B1; board :mini, as: :B2; wire "B1.a1", "B2.a1"')
    result = Breadkit::JumperKit.new({ "wires" => [{ "color" => "red", "usable_span_mm" => 100, "count" => 1 }] }).allocate(resolved)
    expect(result[:assignments]).to be_empty
    expect(result[:skipped]).to eq([{ wire: "W1", reason: "cross-board distance is not modeled" }])
  end

  it "skips solder boards and custom boards without a verified hole pitch" do
    kit = Breadkit::JumperKit.new({ "wires" => [{ "color" => "red", "usable_span_mm" => 100, "count" => 2 }] })
    soldered = circuit('board :universal; wire "a1", "a2"')
    expect(kit.allocate(soldered)[:skipped]).to eq([{ wire: "W1", reason: "solder attachment is not a jumper socket" }])

    builder = Breadkit::DSL::Builder.new
    builder.document.board_definitions << Breadkit::BoardDef.load("mini").data.merge("id" => "custom")
    builder.instance_eval('board :custom; wire "a1", "a2"', "kit.bk.rb", 1)
    custom = Breadkit::Resolver.new.call(builder.document)
    expect(kit.allocate(custom)[:skipped]).to eq([{ wire: "W1", reason: "board pitch is not verified" }])
  end

  it "safely loads an inventory and rejects invalid entries" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "kit.yml")
      File.write(path, "wires:\n  - {color: red, usable_span_mm: 6, count: 2}\n")
      expect(Breadkit::JumperKit.load(path)).to be_a(Breadkit::JumperKit)
      File.write(path, "wires: !ruby/object:Object {}\n")
      expect { Breadkit::JumperKit.load(path) }.to raise_error(ArgumentError)
    end
    [{ "color" => "red", "usable_span_mm" => 0, "count" => 1 },
     { "color" => "red", "usable_span_mm" => 6, "count" => 0 },
     { "color" => "red", "usable_span_mm" => "6", "count" => 1 },
     { "color" => "red", "usable_span_mm" => 6, "count" => 1, "typo" => true }].each do |item|
      expect { Breadkit::JumperKit.new({ "wires" => [item] }) }.to raise_error(ArgumentError)
    end
  end

  it "prints JSON assignments through the CLI" do
    Dir.mktmpdir do |dir|
      source = File.join(dir, "sample.bk.rb")
      kit = File.join(dir, "kit.yml")
      File.write(source, 'board :mini; wire "a1", "a3", color: :red')
      File.write(kit, "wires:\n  - {color: red, usable_span_mm: 6, count: 1}\n")
      output = StringIO.new
      original = $stdout
      $stdout = output
      expect(Breadkit::CLI.new.run(["kit", "--inventory", kit, source])).to eq(0)
      expect(JSON.parse(output.string).fetch("assignments").first.fetch("wire")).to eq("W1")
    ensure
      $stdout = original
    end
  end
end
