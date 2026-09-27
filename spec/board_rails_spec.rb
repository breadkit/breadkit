# frozen_string_literal: true

RSpec.describe Breadkit::Board do
  def definition(rails:, ravine: %w[b c])
    terminal = { "columns" => 4, "rows" => %w[a b c d], "groups" => [%w[a b], %w[c d]] }
    terminal["ravine_between"] = ravine if ravine
    Breadkit::BoardDef.new(
      "id" => "rail_test", "terminal" => terminal, "rails" => rails,
      "rail_layout" => { "segments" => [[1, 4]], "start_row" => 2 }
    )
  end

  it "places left and right rails beside the board, along its rows" do
    rails = [{ "id" => "L", "side" => "left", "order" => 0 },
             { "id" => "R", "side" => "right", "order" => 0 }]
    board = described_class.new(definition(rails: rails))

    expect([board.hole("L1").x, board.hole("L1").y]).to eq([-2.0, 1.0])
    expect([board.hole("L4").x, board.hole("L4").y]).to eq([-2.0, 4.0])
    expect([board.hole("R1").x, board.hole("R1").y]).to eq([5.0, 1.0])
  end

  it "places a center rail inside the defined ravine" do
    board = described_class.new(definition(rails: [{ "id" => "MID", "side" => "center", "order" => 0 }]))

    expect([board.hole("MID1").x, board.hole("MID1").y]).to eq([0.0, 2.0])
    expect([board.hole("MID4").x, board.hole("MID4").y]).to eq([3.0, 2.0])
  end

  it "rejects a center rail that has no free ravine row" do
    rails = [{ "id" => "MID", "side" => "center", "order" => 2 }]
    expect { definition(rails: rails) }.to raise_error(ArgumentError, /center rail/)
    expect { definition(rails: rails, ravine: nil) }.to raise_error(ArgumentError, /center rail/)
  end

  it "rejects rails that would occupy the same physical row" do
    rails = [{ "id" => "PWR", "side" => "left", "order" => 0 },
             { "id" => "RET", "side" => "left", "order" => 0 }]

    expect { definition(rails: rails) }.to raise_error(ArgumentError, /overlap/)
  end
end
