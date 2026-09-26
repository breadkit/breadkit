# frozen_string_literal: true

module Breadkit
  SourceLocation = Struct.new(:path, :line, keyword_init: true)
  Diagnostic = Data.define(:code, :severity, :message, :location, :targets)
  Hole = Struct.new(:id, :kind, :row, :col, :rail, :x, :y, :strip_id, keyword_init: true)
  Strip = Struct.new(:id, :hole_ids, keyword_init: true)
  Pin = Struct.new(:name, :number, :hole_id, :node_id, :role, keyword_init: true)
  Component = Struct.new(:ref, :part, :value, :attrs, :pins, :unused, :location, keyword_init: true) do
    def pin(reference)
      definition = part.pin(reference)
      pins[(definition["name"] || definition["num"]).to_s] if definition
    end
  end
  Wire = Struct.new(:id, :from, :to, :color, :route, :layer, :electrical, :dashed, :location, keyword_init: true)
  Supply = Struct.new(:name, :voltage, :plus, :minus, :location, keyword_init: true)
  Label = Struct.new(:name, :at, :location, keyword_init: true)
  Net = Struct.new(:name, :members, :holes, :labels, :potential, keyword_init: true)

  class Document
    attr_accessor :title, :board, :supplies, :labels, :components, :wires, :expectations,
                  :lint_disables, :part_paths, :part_definitions, :board_paths, :board_definitions

    def initialize
      @title = nil
      @board = { type: "full", options: {} }
      @supplies, @labels, @components, @wires = [], [], [], []
      @expectations, @lint_disables, @part_paths, @part_definitions, @board_paths, @board_definitions = [], [], [], [], [], []
    end
  end
end
