# frozen_string_literal: true

require "tmpdir"
require "stringio"

RSpec.describe Breadkit::CLI do
  def format_output(path)
    original = $stdout
    $stdout = StringIO.new
    expect(described_class.new.run(["fmt", path])).to eq(0)
    $stdout.string
  ensure
    $stdout = original
  end

  it "formats YAML and TOML circuit files without changing their meaning" do
    Dir.mktmpdir do |directory|
      %w[yml toml].each do |extension|
        original = File.expand_path("../examples/0#{extension == 'yml' ? 6 : 7}_declarative_led.bk.#{extension}", __dir__)
        formatted = File.join(directory, "formatted.bk.#{extension}")
        File.write(formatted, format_output(original))
        source = File.read(original, encoding: "UTF-8")
        output = File.read(formatted, encoding: "UTF-8")
        if extension == "toml"
          expect(Tomlrb.parse(output)).to eq(Tomlrb.parse(source))
        else
          expect(YAML.safe_load(output)).to eq(YAML.safe_load(source))
        end
        before = Breadkit.load(original)
        after = Breadkit.load(formatted)
        expect(after.nets.map { |net| [net.name, net.members] }).to eq(before.nets.map { |net| [net.name, net.members] })
        expect(after.components.keys).to eq(before.components.keys)
        expect(after.wires.length).to eq(before.wires.length)
        expect(format_output(formatted)).to eq(File.read(formatted, encoding: "UTF-8"))
      end
    end
  end

  it "rejects executable Ruby files and unsafe YAML" do
    Dir.mktmpdir do |directory|
      source = File.join(directory, "bad.bk.yml")
      File.write(source, "board: !ruby/object:Object {}\n")
      expect(described_class.new.run(["fmt", source])).to eq(2)
      expect(described_class.new.run(["fmt", "circuit.bk.rb"])).to eq(2)
    end
  end

  it "round-trips escaped TOML values and repeated table arrays" do
    data = {
      "title" => "LED \"A\"\nSecond line",
      "board" => "mini",
      "parts" => [
        { "ref" => "R1", "type" => "resistor", "value" => "4.7k 5%", "pins" => %w[a1 a3] },
        { "ref" => "D1", "type" => "led", "pins" => { "anode" => "b3", "cathode" => "b4" } }
      ]
    }
    expect(Tomlrb.parse(Breadkit::Formatter.toml(data))).to eq(data)
  end
end
