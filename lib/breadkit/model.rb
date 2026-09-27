# frozen_string_literal: true

module Breadkit
  module Geometry
    def self.transform(offset, rotate: 0, mirror: false)
      x, y = offset
      x = -x if mirror
      case rotate
      when 90 then [-y, x]
      when 180 then [-x, -y]
      when 270 then [y, -x]
      else [x, y]
      end
    end
  end

  SourceLocation = Struct.new(:path, :line, keyword_init: true)
  Diagnostic = Data.define(:code, :severity, :message, :location, :targets)
  Hole = Struct.new(:id, :kind, :row, :col, :rail, :x, :y, :strip_id, keyword_init: true)
  Strip = Struct.new(:id, :hole_ids, keyword_init: true)
  Pin = Struct.new(:name, :number, :hole_id, :node_id, :role, keyword_init: true)
  Component = Struct.new(:ref, :part, :value, :attrs, :pins, :unused, :location, :step, keyword_init: true) do
    def pin(reference)
      definition = part.pin(reference)
      pins[(definition["name"] || definition["num"]).to_s] if definition
    end

    def provided_sources
      Array(part.data["provides"]).select do |source|
        (source["when"] || {}).all? do |key, expected|
          actual = attrs.key?(key.to_sym) ? attrs[key.to_sym] : attrs[key]
          !actual.nil? && actual.to_s == expected.to_s
        end
      end
    end

    def body_bounds(board)
      render = part.data["render"] || {}
      return unless render["size_mm"]

      holes = pins.values.filter_map { |pin| board.hole(pin.hole_id) if pin.hole_id }
      return if holes.empty?

      width, height = render.fetch("size_mm").map { |value| Float(value) / 2.54 }
      offset = (render["body_offset_mm"] || [0, 0]).map { |value| Float(value) / 2.54 }
      rotate = attrs[:rotate] || 0
      offset_x, offset_y = Geometry.transform(offset, rotate: rotate, mirror: attrs[:mirror] == true)
      width, height = height, width if [90, 270].include?(rotate)
      center_x = (holes.map(&:x).min + holes.map(&:x).max) / 2.0 + offset_x
      center_y = (holes.map(&:y).min + holes.map(&:y).max) / 2.0 + offset_y
      [center_x - width / 2, center_y - height / 2, width, height]
    end
  end
  Wire = Struct.new(:id, :from, :to, :color, :route, :layer, :electrical, :dashed, :location, :step, keyword_init: true)
  Supply = Struct.new(:name, :voltage, :plus, :minus, :location, :isolated, :voltage_range, :current_limit, :step, keyword_init: true)
  Label = Struct.new(:name, :at, :location, :step, keyword_init: true)
  Net = Struct.new(:name, :members, :holes, :labels, :potential, keyword_init: true)

  class Document
    attr_accessor :title, :board, :supplies, :labels, :components, :wires, :expectations,
                  :lint_disables, :part_paths, :part_definitions, :board_paths, :board_definitions, :diagnostics, :source_root, :steps, :boards

    def initialize
      @title = nil
      @board = { type: "full", options: {} }
      @supplies, @labels, @components, @wires = [], [], [], []
      @expectations, @lint_disables, @part_paths, @part_definitions, @board_paths, @board_definitions = [], [], [], [], [], []
      @steps = []
      @boards = []
      @diagnostics = []
    end
  end
end
