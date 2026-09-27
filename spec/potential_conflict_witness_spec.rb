# frozen_string_literal: true

RSpec.describe "power conflict witnesses" do
  def conflicts(source)
    circuit = Breadkit::Resolver.new.call(Breadkit::DSL.load_file("power.bk.rb", source: source))
    circuit.potentials.conflicts
  end

  it "reports the new positive bridge without blaming an existing shared return" do
    source = <<~RUBY
      board :half
      supply :USB, voltage: 5, plus: "B+1", minus: "B-1"
      supply :REG, voltage: 3.3, plus: "T+1", minus: "B-2"
      wire "B+3", "T+3"
    RUBY
    found = conflicts(source)
    expect(found.length).to eq(1)
    expect([found.first[:terminal_a], found.first[:terminal_b]]).to contain_exactly("USB.+", "REG.+")
    expect(found.first[:wires]).to eq(["W1"])
    expect(found.first[:location].line).to eq(4)
  end

  it "reports the new end-to-end bridge without blaming an existing series junction" do
    source = <<~RUBY
      board :half
      supply :POS, voltage: 5, plus: "B+1", minus: "B-1"
      supply :NEG, voltage: 5, plus: "B-2", minus: "T-1"
      wire "B+3", "T-3"
    RUBY
    found = conflicts(source)
    expect(found.length).to eq(1)
    expect([found.first[:terminal_a], found.first[:terminal_b]]).to contain_exactly("POS.+", "NEG.-")
    expect(found.first[:wires]).to eq(["W1"])
    expect(found.first[:location].line).to eq(4)
  end

  it "keeps separate reports when both conflicting bridges use wires" do
    source = <<~RUBY
      board :half
      supply :USB, voltage: 5, plus: "B+1", minus: "B-1"
      supply :REG, voltage: 3.3, plus: "T+1", minus: "T-1"
      wire "B-3", "T-3"
      wire "B+3", "T+3"
    RUBY
    found = conflicts(source)
    expect(found.length).to eq(2)
    expect(found.flat_map { |item| item[:wires] }.uniq).to contain_exactly("W1", "W2")
  end
end
