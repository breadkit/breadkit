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
      unless data.is_a?(Hash) && (data.keys - %w[wires measured_routes]).empty? && data["wires"].is_a?(Array)
        raise ArgumentError, "jumper inventory needs a wires list and optional measured_routes"
      end

      measured = data.fetch("measured_routes", {})
      unless measured.is_a?(Hash) && measured.all? { |id, span| id.is_a?(String) && !id.empty? &&
               span.is_a?(Numeric) && span.real? && span.finite? && span.positive? }
        raise ArgumentError, "invalid measured_routes; use positive millimeter spans keyed by wire ID"
      end
      @measured_routes = measured.transform_values(&:to_f)

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
      unknown = @measured_routes.keys - circuit.wires.map(&:id)
      raise ArgumentError, "measured_routes names unknown wire #{unknown.first}" unless unknown.empty?

      eligible, skipped = [], []
      circuit.wires.each do |wire|
        left, right = [wire.from, wire.to].map { |endpoint| circuit.board.hole(endpoint) }
        reason = skip_reason(circuit, wire, left, right)
        measured_span = @measured_routes[wire.id]
        raise ArgumentError, "measured route #{wire.id} refers to a visual-only wire" if measured_span && wire.electrical == false

        if reason && !measured_span
          skipped << { wire: wire.id, reason: reason }
        else
          modeled_span = Math.hypot(left.x - right.x, left.y - right.y) * 2.54 unless reason
          if modeled_span && measured_span && measured_span + 1e-9 < modeled_span
            raise ArgumentError, "measured route #{wire.id} is shorter than its modeled endpoint span"
          end
          eligible << { wire: wire.id, color: wire.color&.downcase,
                        minimum_span_mm: modeled_span, required_span_mm: measured_span || modeled_span,
                        span_source: measured_span ? "measured" : "board_geometry" }
        end
      end

      candidates = eligible.to_h do |wire|
        compatible = @slots.each_index.select do |index|
          slot = @slots.fetch(index)
          (!wire[:color] || slot[:color] == wire[:color]) && slot[:usable_span_mm] + 1e-9 >= wire[:required_span_mm]
        end.sort_by { |index| [@slots[index][:usable_span_mm], @slots[index][:color], index] }
        [wire[:wire], compatible]
      end
      owners, assigned = {}, {}
      eligible.sort_by { |wire| [candidates.fetch(wire[:wire]).length, -wire[:required_span_mm], wire[:wire]] }
        .each { |wire| assign(wire[:wire], candidates, owners, assigned, {}) }

      assignments = eligible.filter_map do |wire|
        slot = @slots[assigned[wire[:wire]]] if assigned.key?(wire[:wire])
        { wire: wire[:wire], color: slot[:color], usable_span_mm: slot[:usable_span_mm],
          minimum_span_mm: wire[:minimum_span_mm]&.round(2),
          required_span_mm: wire[:required_span_mm].round(2), span_source: wire[:span_source] } if slot
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
