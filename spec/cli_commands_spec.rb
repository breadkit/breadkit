# frozen_string_literal: true

require "tmpdir"

RSpec.describe Breadkit::CLI do
  let(:cli) { described_class.new }
  let(:example) { File.expand_path("../examples/01_led_button.bk.rb", __dir__) }

  it "shows and validates part definitions" do
    expect { cli.run(%w[parts show led]) }.to output(/"id": "led"/).to_stdout
    path = File.expand_path("../data/parts/led.yml", __dir__)
    expect { cli.run(["check-part", path]) }.to output(/Valid part: led/).to_stdout
    expect(cli.run(["check-part", "missing.yml"])).to eq(2)
  end

  it "explains a hole and a component without inventing current" do
    expect { cli.run(["where", "a10", example]) }
      .to output(/Strip: a10, b10, c10, d10, e10.*Net: VCC.*Pins: SW1\.1@e10.*Wires: W1@a10/m).to_stdout
    expect { cli.run(["explain", "R1", example]) }
      .to output(/R1: resistor 330.*Current: unknown/m).to_stdout
    expect(cli.run(["where", "z99", example])).to eq(2)
  end

  it "calculates resistor current only when both terminal potentials are constrained" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "resistor.bk.rb")
      File.write(path, 'board :mini; supply :USB, voltage: 5, plus: "a1", minus: "a2"; resistor :R1, "1k", pins: %w[b1 b2]')
      expect { cli.run(["explain", "R1", path]) }.to output(/Current: 0\.005 A/).to_stdout
    end
  end

  it "summarizes components and wires and compares circuit revisions" do
    expect { cli.run(["bom", example]) }.to output(/1\tresistor\t330.*2\tjumper_wire/m).to_stdout
    Dir.mktmpdir do |dir|
      modified = File.join(dir, "modified.bk.rb")
      File.write(modified, File.read(example, encoding: "UTF-8").sub('"330"', '"470"'))
      expect { cli.run(["diff", example, modified]) }
        .to output(/- component R1: resistor 330.*\+ component R1: resistor 470/m).to_stdout
    end
  end

  it "creates each packaged template and refuses to overwrite it" do
    Dir.mktmpdir do |dir|
      %w[led 555 arduino].each do |name|
        path = File.join(dir, "#{name}.bk.rb")
        expect(cli.run(["new", path, "--template", name])).to eq(0)
        expect(File.read(path, encoding: "UTF-8")).to include("board :half")
        expect(Breadkit.load(path).diagnostics.select { |item| item.severity == "error" }).to be_empty
        expect(cli.run(["new", path, "--template", name])).to eq(2)
      end
    end
  end
end
