# frozen_string_literal: true

RSpec.describe Breadkit::Exporters do
  def circuit(source)
    builder = Breadkit::DSL::Builder.new(base_dir: File.expand_path("../examples", __dir__))
    builder.instance_eval(source, "export.bk.rb", 1)
    Breadkit::Resolver.new.call(builder.document)
  end

  it "exports connected pin numbers in a KiCad XML netlist" do
    input = Breadkit.load(File.expand_path("../examples/03_arduino_blink.bk.rb", __dir__))
    output = described_class.call(input, format: "kicad")
    expect(output).to include('<export version="E">', '<libpart lib="breadkit" part="resistor">')
    expect(output).to include('<node ref="UNO" pin="14"/>', '<node ref="R1" pin="1"/>')
    expect(output).not_to include('<net code="27" name="N27">')
  end

  it "exports a passive circuit as a SPICE operating-point netlist" do
    input = circuit('board :mini; supply :USB, voltage: 5, plus: "a1", minus: "a2"; resistor :R1, "1k", pins: %w[b1 b2]; capacitor :C1, "10u", pins: %w[c1 c2]')
    output = described_class.call(input, format: "spice")
    expect(output).to include("VUSB N1 0 5", "R1 N1 0 1000", "C1 N1 0 1e-05", ".op\n.end")
    with_led = circuit('board :mini; led :D1, anode: "a1", cathode: "a2"; supply :USB, voltage: 5, plus: "b1", minus: "b2"')
    expect { described_class.call(with_led, format: "spice") }.to raise_error(ArgumentError, /only resistors and capacitors/)
    ranged = circuit('board :mini; supply :USB, voltage: 3.0..4.2, plus: "a1", minus: "a2"; resistor :R1, "1k", pins: %w[b1 b2]')
    expect { described_class.call(ranged, format: "spice") }.to raise_error(ArgumentError, /fixed supply voltages/)
  end

  it "exports Arduino, resistor and LED nets as Wokwi connections" do
    input = Breadkit.load(File.expand_path("../examples/03_arduino_blink.bk.rb", __dir__))
    result = JSON.parse(described_class.call(input, format: "wokwi"))
    expect(result.fetch("version")).to eq(1)
    expect(result.fetch("parts").map { |item| item.fetch("type") }).to eq(%w[wokwi-arduino-uno wokwi-resistor wokwi-led])
    expect(result.fetch("connections")).to include(["UNO:13", "R1:1", "yellow", []], ["R1:2", "D1:A", "green", []],
                                                   ["UNO:GND.1", "D1:C", "black", []])
    unsupported = Breadkit.load(File.expand_path("../examples/02_555_blinker.bk.rb", __dir__))
    expect { described_class.call(unsupported, format: "wokwi") }.to raise_error(ArgumentError, /standalone supplies/)
  end

  it "exports Arduino and RP2040 pin constants only for connected GPIO" do
    uno = Breadkit.load(File.expand_path("../examples/03_arduino_blink.bk.rb", __dir__))
    expect(described_class.call(uno, format: "pins")).to include("#pragma once", "#define PIN_R1_1 13")
    pico = circuit('use_parts "parts/pico_w.yml"; board :full; part :PICO, :pico_w, at: "d1"; resistor :R1, "1k", pins: %w[a1 f2]')
    expect(pico.diagnostics.select { |item| item.severity == "error" }).to be_empty
    expect(described_class.call(pico, format: "pins")).to include("# MicroPython GPIO constants", "PIN_R1_1 = 0")
  end

  it "rejects export of unresolved circuits" do
    invalid = circuit('board :mini; resistor :R1, "1k", pins: %w[a1 z1]')
    expect { described_class.call(invalid, format: "kicad") }.to raise_error(ArgumentError, /cannot export a circuit with errors/)
  end

  it "exposes export through the CLI with explicit format selection" do
    path = File.expand_path("../examples/03_arduino_blink.bk.rb", __dir__)
    cli = Breadkit::CLI.new
    status = nil
    expect { status = cli.run(["export", "--format", "wokwi", path]) }.to output(/"version": 1/).to_stdout
    expect(status).to eq(0)
    expect { status = cli.run(["export", "--format", "unknown", path]) }
      .to output(/choose --format/).to_stderr
    expect(status).to eq(2)
  end
end
