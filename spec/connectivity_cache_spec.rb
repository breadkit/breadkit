# frozen_string_literal: true

RSpec.describe "switch-state connectivity snapshots" do
  def circuit
    source = <<~RUBY
      board :half
      supply :USB, voltage: 5, plus: "B+1", minus: "B-1"
      supply :REG, voltage: 3.3, plus: "T+1", minus: "B-2"
      button :SW1, at: "e10"
      button :SW2, at: "e20"
      wire "B+3", "a10"
      wire "T+3", "a12"
    RUBY
    Breadkit::Resolver.new.call(Breadkit::DSL.load_file("states.bk.rb", source: source))
  end

  def signature(circuit, state)
    nets = circuit.nets(state).map do |net|
      [net.name, net.members.sort, net.holes.sort, net.labels.sort, net.potential]
    end
    conflicts = circuit.potentials(state).conflicts.map do |item|
      [item[:terminal_a], item[:terminal_b], item[:path], item[:wires]]
    end
    [nets, conflicts]
  end

  it "copies static unions without sharing state-dependent changes" do
    original = Breadkit::UnionFind.new
    original.union("a", "b")
    copy = original.snapshot
    copy.union("b", "c")

    expect(original.find("a")).to eq(original.find("b"))
    expect(original.find("a")).not_to eq(original.find("c"))
    expect(copy.find("a")).to eq(copy.find("c"))
  end

  it "matches fresh circuits after computing switch states in a different order" do
    reused = circuit
    states = reused.states("single")
    states.reverse_each { |state| reused.nets(state) }
    states.each do |state|
      fresh = circuit
      fresh_state = fresh.states("single").find { |candidate| candidate.name == state.name }
      expect(signature(reused, state)).to eq(signature(fresh, fresh_state))
    end
  end
end
