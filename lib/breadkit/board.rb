# frozen_string_literal: true

module Breadkit
  class BoardDef
    attr_reader :data

    def initialize(data)
      @data = data
      terminal = data["terminal"] || {}
      unless data["id"] && terminal["columns"].to_i.positive? && terminal["rows"].is_a?(Array) && terminal["groups"].is_a?(Array)
        raise ArgumentError, "invalid board definition: #{data['id'] || '(missing id)'}"
      end
      rows = terminal.fetch("rows").map(&:to_s)
      rails = Array(data["rails"]).map { |rail| rail.fetch("id").to_s }
      unless Array(data["rails"]).all? { |rail| !rail.key?("polarity") || %w[+ -].include?(rail["polarity"]) }
        raise ArgumentError, "invalid rail polarity"
      end
      raise ArgumentError, "duplicate row name" unless rows.map(&:downcase).uniq.length == rows.length
      raise ArgumentError, "duplicate rail name" unless rails.map(&:downcase).uniq.length == rails.length
      [rows, rails].each do |kind_names|
        if kind_names.any? { |name| kind_names.any? { |other| name != other && other.downcase.match?(/\A#{Regexp.escape(name.downcase)}\d+\z/) } }
          raise ArgumentError, "ambiguous board row or rail names"
        end
      end
      names = (rows + rails).map(&:downcase)
      unless names.all? { |name| name.match?(/\A[a-z][a-z0-9_+\-]*\z/) }
        raise ArgumentError, "invalid board row or rail name"
      end
      if rows.any? { |row| rails.any? { |rail| rail.casecmp?(row) || rail.downcase.match?(/\A#{Regexp.escape(row.downcase)}\d+\z/) || row.downcase.match?(/\A#{Regexp.escape(rail.downcase)}\d+\z/) } }
        raise ArgumentError, "board row and rail names must not overlap"
      end
      groups = terminal.fetch("groups")
      grouped_rows = groups.flat_map { |group| Array(group).map(&:to_s) }
      unless groups.all? { |group| group.is_a?(Array) && !group.empty? } && grouped_rows.sort == rows.sort
        raise ArgumentError, "terminal groups must partition rows exactly"
      end
      if terminal.key?("ravine_between")
        ravine = terminal["ravine_between"]
        unless ravine.is_a?(Array) && ravine.length == 2 && rows.each_cons(2).any? { |pair| pair == ravine.map(&:to_s) }
          raise ArgumentError, "ravine_between must name adjacent terminal rows"
        end
      end
    end

    def id
      data.fetch("id")
    end

    def self.load(id, extra_paths: [], extra_definitions: [])
      paths = extra_paths.flat_map { |path| Dir.glob(path) }
      paths.concat(Dir.glob(File.expand_path("../../data/boards/*.yml", __dir__)))
      data = extra_definitions.find { |item| item["id"].to_s == id.to_s }
      data ||= paths.uniq.lazy.map { |path| YAML.safe_load(File.read(path, encoding: "UTF-8"), aliases: false) }.find { |item| item && item["id"].to_s == id.to_s }
      raise ArgumentError, "unknown board: #{id}" unless data

      new(data)
    end
  end

  class Board
    attr_reader :definition, :holes, :strips, :split_rails

    def initialize(definition, split_rails: false)
      @definition, @split_rails = definition, split_rails
      @holes, @strips = {}, {}
      @terminal_rows = definition.data.dig("terminal", "rows")
      ravine = Array(definition.data.dig("terminal", "ravine_between")).map(&:to_s)
      @terminal_row_positions = {}
      position = 0
      @terminal_rows.each_with_index do |row, index|
        position += 2 if index.positive? && [@terminal_rows[index - 1].to_s, row.to_s] == ravine
        @terminal_row_positions[row.to_s] = position
        position += 1
      end
      build_terminal_holes
      build_rail_holes
    end

    def hole(id)
      holes[HoleId.parse(id, board: self).to_s]
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
      @terminal_rows.empty? ? 0 : @terminal_row_positions.fetch(@terminal_rows.last.to_s) + 1
    end

    def row_count
      @terminal_rows.length
    end

    def terminal_rows
      @terminal_rows.map(&:to_s)
    end

    def ravine_between
      Array(definition.data.dig("terminal", "ravine_between")).map(&:to_s)
    end

    def rail_ids
      definition.data.fetch("rails", []).map { |rail| rail.fetch("id").to_s }
    end

    def rail_polarity(id)
      rail = definition.data.fetch("rails", []).find { |item| item.fetch("id").to_s.casecmp?(id.to_s) }
      rail && (rail["polarity"] || rail.fetch("id").to_s[/[+-]\z/])
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
                              col: col + 1, x: col.to_f, y: @terminal_row_positions.fetch(row.to_s).to_f,
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
