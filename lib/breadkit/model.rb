# frozen_string_literal: true

module Breadkit
  SourceLocation = Struct.new(:path, :line, keyword_init: true)
  Diagnostic = Struct.new(:code, :severity, :message, :location, :targets, keyword_init: true)
  Hole = Struct.new(:id, :kind, :row, :col, :rail, :x, :y, :strip_id, keyword_init: true)
  Strip = Struct.new(:id, :hole_ids, keyword_init: true)
  Pin = Struct.new(:name, :number, :hole_id, :node_id, :role, keyword_init: true)
  Component = Struct.new(:ref, :part, :value, :attrs, :pins, :unused, :location, keyword_init: true)
  Wire = Struct.new(:id, :from, :to, :color, :route, :location, keyword_init: true)
  Supply = Struct.new(:name, :voltage, :plus, :minus, :location, keyword_init: true)
  Label = Struct.new(:name, :at, :location, keyword_init: true)
  Net = Struct.new(:name, :members, :holes, :labels, :potential, keyword_init: true)

  class Document
    attr_accessor :title, :board, :supplies, :labels, :components, :wires, :expectations,
                  :lint_disables, :part_paths, :board_paths

    def initialize
      @title = nil
      @board = { type: "full", options: {} }
      @supplies, @labels, @components, @wires = [], [], [], []
      @expectations, @lint_disables, @part_paths, @board_paths = [], [], [], []
    end
  end
end
