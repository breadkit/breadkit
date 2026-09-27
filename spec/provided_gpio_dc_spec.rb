# frozen_string_literal: true

RSpec.describe "DC current for a declared provided output" do
  def circuit(source)
    builder = Breadkit::DSL::Builder.new
    builder.document.part_definitions << {
      "id" => "test_controller", "placement" => "offboard",
      "pins" => [{ "num" => 1, "name" => "OUT", "type" => "gpio", "max_current" => 0.012 },
                 { "num" => 2, "name" => "GND", "type" => "ground" },
                 { "num" => 3, "name" => "AUX", "type" => "gpio" }],
      "provides" => [{ "positive" => "OUT", "negative" => "GND", "voltage" => 3.3 }]
    }
    builder.instance_eval(source, "current.bk.rb", 1)
    Breadkit::Resolver.new.call(builder.document)
  end

  it "uses the explicit provided voltage source to solve its GPIO current" do
    resolved = circuit('board :mini; offboard :U1, :test_controller; resistor :R1, "330", pins: %w[a1 a2]; wire "U1.OUT", "b1"; wire "U1.GND", "b2"')
    result = resolved.dc_analysis
    expect(result.status).to eq(:ok)
    expect(result.currents.fetch("U1.OUT").abs).to be_within(1e-9).of(0.01)
  end

  it "still treats an ordinary connected GPIO as an unknown output state" do
    resolved = circuit('board :mini; offboard :U1, :test_controller; resistor :R1, "330", pins: %w[a1 a2]; wire "U1.AUX", "b1"; wire "U1.GND", "b2"')
    result = resolved.dc_analysis
    expect(result.status).to eq(:unsupported)
    expect(result.errors.join).to include("output state")
    expect(result.currents).to be_empty
  end
end
