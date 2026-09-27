# frozen_string_literal: true

RSpec.describe "Switch state budgets" do
  def circuit_with_switches(count)
    builder = Breadkit::DSL::Builder.new
    source = (["board :full"] + (1..count).map { |number| "button :SW#{number}, at: \"e#{number * 4 - 3}\"" }).join("\n")
    builder.instance_eval(source, "states.bk.rb", 1)
    Breadkit::Resolver.new.call(builder.document)
  end

  it "enumerates all combinations within an explicit budget" do
    circuit = circuit_with_switches(3)
    expect(circuit.states("all", budget: 8).map(&:name)).to include(nil, "SW1,SW2,SW3")
    expect(circuit.states("all", budget: 8).length).to eq(8)
  end

  it "raises instead of silently omitting combinations when the budget is too small" do
    circuit = circuit_with_switches(3)
    expect { circuit.states("all", budget: 7) }.to raise_error(ArgumentError, /8.*budget.*7/)
    expect { circuit.states("all", budget: 0) }.to raise_error(ArgumentError, /positive integer/)
  end

  it "retains the legacy fallback unless a sufficient budget is explicitly requested" do
    circuit = circuit_with_switches(9)
    expect(circuit.states("all").length).to eq(11)
    expect(circuit.states("all", budget: 512).length).to eq(512)
  end
end
