# frozen_string_literal: true

module Breadkit
  class JumperKit
    MAX_JUMPERS = 1000
    VERIFIED_BOARDS = %w[mini half full double_full].freeze

    def self.load(path)
      source = File.read(path, encoding: "UTF-8")
      data = case File.extname(path).downcase
             when ".yml", ".yaml" then YAML.safe_load(source, aliases: false)
             when ".json" then JSON.parse(source)
             else raise ArgumentError, "jumper inventory must be YAML or JSON"
             end
      new(data)
    rescue Psych::Exception, JSON::ParserError => error
      raise ArgumentError, "invalid jumper inventory: #{error.message}"
    end

    def initialize(data)
      raise ArgumentError, "jumper inventory needs only a wires list" unless data.is_a?(Hash) && data.keys == ["wires"] && data["wires"].is_a?(Array)

      @slots = data.fetch("wires").flat_map do |item|
        unless item.is_a?(Hash) && (item.keys - %w[color usable_span_mm count]).empty? &&
               %w[color usable_span_mm count].all? { |key| item.key?(key) }
          raise ArgumentError, "invalid jumper inventory entry"
        end

        color, span, count = item.values_at("color", "usable_span_mm", "count")
        unless color.is_a?(String) && !color.strip.empty? && span.is_a?(Numeric) && span.real? &&
               span.finite? && span.positive? && count.is_a?(Integer) && count.positive? && count <= MAX_JUMPERS
          raise ArgumentError, "invalid jumper color, usable_span_mm, or count"
        end

        Array.new(count) { { color: color.downcase, usable_span_mm: span.to_f } }
      end
      raise ArgumentError, "jumper inventory exceeds #{MAX_JUMPERS} pieces" if @slots.length > MAX_JUMPERS
    end

    def allocate(circuit)
      raise ArgumentError, "circuit has errors" if circuit.diagnostics.any? { |item| item.severity == "error" }

      eligible, skipped = [], []
      circuit.wires.each do |wire|
        left, right = [wire.from, wire.to].map { |endpoint| circuit.board.hole(endpoint) }
        reason = skip_reason(circuit, wire, left, right)
        if reason
          skipped << { wire: wire.id, reason: reason }
        else
          eligible << { wire: wire.id, color: wire.color&.downcase,
                        minimum_span_mm: Math.hypot(left.x - right.x, left.y - right.y) * 2.54 }
        end
      end

      candidates = eligible.to_h do |wire|
        compatible = @slots.each_index.select do |index|
          slot = @slots.fetch(index)
          (!wire[:color] || slot[:color] == wire[:color]) && slot[:usable_span_mm] + 1e-9 >= wire[:minimum_span_mm]
        end.sort_by { |index| [@slots[index][:usable_span_mm], @slots[index][:color], index] }
        [wire[:wire], compatible]
      end
      owners, assigned = {}, {}
      eligible.sort_by { |wire| [candidates.fetch(wire[:wire]).length, -wire[:minimum_span_mm], wire[:wire]] }
        .each { |wire| assign(wire[:wire], candidates, owners, assigned, {}) }

      assignments = eligible.filter_map do |wire|
        slot = @slots[assigned[wire[:wire]]] if assigned.key?(wire[:wire])
        { wire: wire[:wire], color: slot[:color], usable_span_mm: slot[:usable_span_mm],
          minimum_span_mm: wire[:minimum_span_mm].round(2) } if slot
      end
      unassigned = eligible.reject { |wire| assigned.key?(wire[:wire]) }
        .map { |wire| { wire: wire[:wire], reason: "no compatible jumper in inventory" } }
      { assignments: assignments, unassigned: unassigned, skipped: skipped }
    end

    private

    def skip_reason(circuit, wire, left, right)
      return "visual-only wire" if wire.electrical == false
      return "route length is not modeled" unless wire.route == "straight"
      return "both endpoints must be board holes" unless left && right
      return "cross-board distance is not modeled" if circuit.multi_board? && left.id.split(".", 2).first != right.id.split(".", 2).first
      return "rail distance is not modeled" unless left.kind == :terminal && right.kind == :terminal
      return "solder attachment is not a jumper socket" if circuit.board.solder_pad?(left.id) || circuit.board.solder_pad?(right.id)
      board = circuit.multi_board? ? circuit.boards.fetch(left.id.split(".", 2).first) : circuit.board
      return "board pitch is not verified" unless VERIFIED_BOARDS.include?(board.definition.id) &&
                                                 board.definition.data == BoardDef.load(board.definition.id).data

      nil
    end

    def assign(wire_id, candidates, owners, assigned, seen)
      candidates.fetch(wire_id).each do |index|
        next if seen[index]

        seen[index] = true
        previous = owners[index]
        next if previous && !assign(previous, candidates, owners, assigned, seen)

        owners[index] = wire_id
        assigned[wire_id] = index
        return true
      end
      false
    end
  end
end
