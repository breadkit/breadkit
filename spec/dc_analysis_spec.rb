# frozen_string_literal: true

require_relative "../lib/breadkit/dc_analysis"

RSpec.describe Breadkit::DCAnalysis do
  def resolve(source)
    builder = Breadkit::DSL::Builder.new
    builder.instance_eval(source, "dc.bk.rb", 1)
    Breadkit::Resolver.new.call(builder.document)
  end

  it "solves a grounded resistor divider and reports currents and dissipation" do
    circuit = resolve(<<~DSL)
      board :mini
      supply :BAT, voltage: 6, plus: "b1", minus: "b5"
      net :GND, at: "a5"
      resistor :R1, "1k", pins: %w[a1 a3]
      resistor :R2, "2k", pins: %w[b3 a5]
    DSL
    result = circuit.dc_analysis

    expect(result).to be_success
    expect(result.floating).to be_empty
    expect(result.voltages.fetch(circuit.net_of("a3").name)).to be_within(1e-9).of(4.0)
    expect(result.currents.values_at("R1", "R2")).to all(be_within(1e-9).of(0.002))
    expect(result.power).to include("R1" => be_within(1e-9).of(0.004), "R2" => be_within(1e-9).of(0.008))
  end

  it "uses a fixed-drop LED model and opens a reverse-biased LED" do
    forward = resolve(<<~DSL)
      board :mini
      supply :BAT, voltage: 5, plus: "b1", minus: "b5"
      net :GND, at: "a5"
      resistor :R1, "330", pins: %w[a1 a3]
      led :D1, anode: "b3", cathode: "a5"
    DSL
    result = forward.dc_analysis
    current = 3.0 / 331.0
    expect(result).to be_success
    expect(result.currents.fetch("D1")).to be_within(1e-9).of(current)
    expect(result.currents.fetch("R1")).to be_within(1e-9).of(current)
    expect(result.power.fetch("R1")).to be_within(1e-9).of(current * current * 330)
    expect(result.assumptions.join).to include("2.0 V forward drop")

    reverse = resolve(<<~DSL)
      board :mini
      supply :BAT, voltage: 5, plus: "b1", minus: "b5"
      net :GND, at: "a5"
      resistor :R1, "330", pins: %w[a1 a3]
      led :D1, anode: "a5", cathode: "b3"
    DSL
    reverse_result = reverse.dc_analysis
    expect(reverse_result).to be_success
    expect(reverse_result.currents.values_at("D1", "R1")).to eq([0.0, 0.0])
  end

  it "uses part-defined forward voltage and on resistance" do
    builder = Breadkit::DSL::Builder.new
    builder.document.part_definitions << {
      "id" => "led", "override" => true, "category" => "diode", "placement" => "leads",
      "pins" => [{ "num" => 1, "name" => "anode" }, { "num" => 2, "name" => "cathode" }],
      "polarity" => { "positive" => "anode", "negative" => "cathode" },
      "forward_voltage" => 3.0, "on_resistance" => 2.0
    }
    builder.instance_eval('board :mini; supply :BAT, voltage: 5, plus: "b1", minus: "b5"; resistor :R1, "330", pins: %w[a1 a3]; led :D1, anode: "b3", cathode: "a5"', "calibrated.bk.rb", 1)
    result = Breadkit::Resolver.new.call(builder.document).dc_analysis
    expect(result.currents.fetch("D1")).to be_within(1e-9).of(2.0 / 332.0)
  end

  it "marks an ungrounded supply domain as relative" do
    circuit = resolve('board :mini; supply :BAT, voltage: 5, plus: "b1", minus: "b5"; resistor :R1, "1k", pins: %w[a1 a5]')
    result = circuit.dc_analysis

    expect(result).to be_success
    expect(result.floating).to contain_exactly(contain_exactly(circuit.net_of("a1").name, circuit.net_of("a5").name))
    expect(result.voltages.fetch(circuit.net_of("a1").name) - result.voltages.fetch(circuit.net_of("a5").name)).to eq(5.0)
  end

  it "uses the requested switch state" do
    circuit = resolve(<<~DSL)
      board :mini
      supply :BAT, voltage: 5, plus: "b1", minus: "b7"
      net :GND, at: "a7"
      resistor :R1, "1k", pins: %w[a1 a3]
      part :SW1, :slide_switch_spst, pins: %w[b3 a5]
      resistor :R2, "1k", pins: %w[b5 a7]
    DSL
    expect(circuit.dc_analysis.currents.fetch("R1")).to eq(0.0)
    closed = circuit.states.find { |state| state.name == "SW1" }
    expect(circuit.dc_analysis(closed).currents.fetch("R1")).to be_within(1e-9).of(0.0025)
  end

  it "bounds current and power across source voltage and resistor tolerance" do
    circuit = resolve(<<~DSL)
      board :mini
      supply :BAT, voltage: 3.0..4.2, plus: "b1", minus: "b5"
      resistor :R1, "100 5%", pins: %w[a1 a5]
    DSL
    result = circuit.dc_analysis(nil, worst_case: true)

    expect(result).to be_success
    expect(result.bounds_status).to eq(:ok)
    expect(result.currents.fetch("R1")).to be_within(1e-9).of(0.036)
    expect(result.current_ranges.fetch("R1")).to eq([3.0 / 105.0, 4.2 / 95.0])
    expect(result.power_ranges.fetch("R1").first).to be_within(1e-9).of(3.0**2 / 105.0)
    expect(result.power_ranges.fetch("R1").last).to be_within(1e-9).of(4.2**2 / 95.0)
  end

  it "bounds a divider voltage with both resistor tolerances" do
    circuit = resolve(<<~DSL)
      board :mini
      supply :BAT, voltage: 5, plus: "b1", minus: "b7"
      resistor :R1, "1k 5%", pins: %w[a1 a3]
      resistor :R2, "1k 5%", pins: %w[b3 a7]
    DSL
    result = circuit.dc_analysis(nil, worst_case: true)
    midpoint = circuit.net_of("a3").name

    expect(result.bounds_status).to eq(:ok)
    expect(result.voltage_ranges.fetch(midpoint).first).to be_within(1e-9).of(2.375)
    expect(result.voltage_ranges.fetch(midpoint).last).to be_within(1e-9).of(2.625)
  end

  it "reports when exact bounds exceed the scenario budget" do
    declarations = (1..10).map do |number|
      "supply :S#{number}, voltage: 3.0..4.2, plus: 'a#{number * 2 - 1}', minus: 'a#{number * 2}'"
    end
    circuit = resolve((["board :full"] + declarations).join("\n"))
    result = circuit.dc_analysis(nil, worst_case: true)

    expect(result).to be_success
    expect(result.bounds_status).to eq(:too_complex)
    expect(result.current_ranges).to be_nil
  end

  it "does not assign an invented voltage to a diode without a return path" do
    circuit = resolve('board :mini; led :D1, anode: "a1", cathode: "a3"')
    result = circuit.dc_analysis

    expect(result.status).to eq(:indeterminate)
    expect(result.voltages).to be_empty
  end

  it "reports unsupported and inconsistent circuits instead of returning invented values" do
    active = resolve('board :mini; transistor :Q1, pins: %w[a1 a3 a5]')
    expect(active.dc_analysis.status).to eq(:unsupported)

    conflict = resolve('board :mini; supply :A, voltage: 5, plus: "a1", minus: "a5"; supply :B, voltage: 3, plus: "b1", minus: "b5"')
    expect(conflict.dc_analysis.status).to eq(:singular)
    expect(conflict.dc_analysis.voltages).to be_empty

    gpio = resolve('board :mini; offboard :UNO, :arduino_uno; resistor :R1, "1k", pins: %w[a1 a3]; wire "b1", "UNO.D13"; wire "b3", "UNO.GND"')
    expect(gpio.dc_analysis.status).to eq(:unsupported)
  end
end
