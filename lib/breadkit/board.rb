# frozen_string_literal: true

module Breadkit
  class BoardDef
    attr_reader :data

    def initialize(data)
      @data = data
    end

    def id
      data.fetch("id")
    end

    def self.load(id, extra_paths: [])
      paths = extra_paths.flat_map { |path| Dir.glob(path) }
      paths.concat(Dir.glob(File.expand_path("../../data/boards/*.yml", __dir__)))
      data = paths.uniq.lazy.map { |path| YAML.safe_load(File.read(path), aliases: false) }.find { |item| item && item["id"].to_s == id.to_s }
      raise ArgumentError, "unknown board: #{id}" unless data

      new(data)
    end
  end

  class Board
    attr_reader :definition, :holes, :strips, :split_rails

    def initialize(definition, split_rails: false)
      @definition, @split_rails = definition, split_rails
      @holes, @strips = {}, {}
      build_terminal_holes
      build_rail_holes
    end

    def hole(id)
      holes[HoleId.parse(id).to_s]
    rescue ArgumentError
      nil
    end

    def strip(id)
      item = hole(id)
      item && strips[item.strip_id]
    end

    def width
      definition.data.dig("terminal", "columns").to_i
    end

    def height
      definition.data.dig("terminal", "rows").length
    end

    private

    def add_hole(hole)
      holes[hole.id] = hole
      (strips[hole.strip_id] ||= []) << hole.id
    end

    def build_terminal_holes
      terminal = definition.data.fetch("terminal")
      groups = terminal.fetch("groups")
      terminal.fetch("columns").times do |col|
        groups.each_with_index do |rows, group_index|
          strip_id = "terminal:#{col + 1}:#{group_index}"
          rows.each do |row|
            add_hole(Hole.new(id: "#{row}#{col + 1}", kind: :terminal, row: row.to_s,
                              col: col + 1, x: col.to_f, y: terminal.fetch("rows").index(row).to_f,
                              strip_id: strip_id))
          end
        end
      end
    end

    def build_rail_holes
      layout = definition.data["rail_layout"]
      return unless layout

      definition.data.fetch("rails", []).each do |rail|
        rail_id = rail.fetch("id")
        segments = layout.fetch("segments")
        segments = layout.fetch("split_segments", segments) if split_rails
        segments.each_with_index do |range, segment_index|
          (range[0]..range[1]).each do |index|
            x = layout.fetch("start_column", 1) - 1 + index - 1
            size = layout["group_size"].to_i
            x += (index - 1) / size if size.positive?
            y = rail.fetch("side") == "top" ? height + 1 + rail.fetch("order", 0) : -2 - rail.fetch("order", 0)
            strip_id = "rail:#{rail_id}:#{segment_index}"
            add_hole(Hole.new(id: "#{rail_id}#{index}", kind: :rail, rail: rail_id,
                              col: index, x: x.to_f, y: y.to_f, strip_id: strip_id))
          end
        end
      end
    end
  end
end
