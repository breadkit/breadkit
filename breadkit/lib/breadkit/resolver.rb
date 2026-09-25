# frozen_string_literal: true

module Breadkit
  class Resolver
    def call(document)
      @document = document
      @diagnostics = []
      @board = load_board
      @library = PartLibrary.new(extra_paths: document.part_paths)
      components = resolve_components
      wires = resolve_wires(components)
      supplies = resolve_supplies
      labels = document.labels.map { |item| Label.new(name: item[:name], at: item[:at], location: item[:location]) }
      validate_references(components, supplies, labels)
      Circuit.new(title: document.title, board: @board, components: components, wires: wires,
                  supplies: supplies, labels: labels, expectations: document.expectations,
                  lint_disables: document.lint_disables, diagnostics: @diagnostics)
    end

    private

    def load_board
      Board.new(BoardDef.load(@document.board[:type], extra_paths: @document.board_paths),
                split_rails: @document.board[:options][:split_rails] || false)
    rescue StandardError => e
      @diagnostics << diagnostic(:unknown_part, "error", e.message, nil)
      Board.new(BoardDef.load("full"))
    end

    def resolve_components
      refs = {}
      @document.components.each_with_object({}) do |item, result|
        ref = item[:ref]
        if refs[ref]
          @diagnostics << diagnostic(:duplicate_ref, "error", "duplicate component reference #{ref}", item[:location], [ref])
          next
        end
        refs[ref] = true
        part = @library.find(item[:type], pin_count: item.dig(:attrs, :pin_count) || item.dig(:attrs, "pin_count"))
        unless part
          @diagnostics << diagnostic(:unknown_part, "error", "unknown part #{item[:type]}", item[:location], [ref])
          next
        end
        pins = resolve_pins(item, part)
        result[ref] = Component.new(ref: ref, part: part, value: item[:value], attrs: item[:attrs] || {},
                                    pins: pins, unused: Array(item[:unused]).map(&:to_s), location: item[:location])
      end
    end

    def resolve_pins(item, part)
      requested = item[:pins]
      result = {}
      part.pins.each_with_index do |definition, index|
        name, number = definition["name"] || definition["num"].to_s, definition["num"].to_s
        anchor = explicit_pin(requested, definition, index)
        anchor ||= explicit_pin(item[:attrs], definition, index)
        if anchor.nil? && item[:at]
          anchor = footprint_pin(item, definition, part)
        end
        if anchor
          hole = @board.hole(anchor)
          unless hole
            if part.placement == "dip"
              @diagnostics << diagnostic(:invalid_placement, "error", "DIP #{item[:ref]} extends beyond the board", item[:location], [item[:ref], anchor])
            else
              @diagnostics << diagnostic(:invalid_hole, "error", "invalid hole #{anchor.inspect}", item[:location], [item[:ref], anchor])
            end
          end
          result[name.to_s] = Pin.new(name: name.to_s, number: number, hole_id: hole&.id,
                                      node_id: "pin:#{item[:ref]}.#{name}", role: definition["role"])
        else
          result[name.to_s] = Pin.new(name: name.to_s, number: number, node_id: "pin:#{item[:ref]}.#{name}",
                                      role: definition["role"])
        end
      end
      result
    end

    def explicit_pin(source, definition, index)
      return nil unless source
      if source.is_a?(Array)
        return source[index]
      end
      return nil unless source.respond_to?(:each_pair)
      ([definition["num"], definition["name"]] + Array(definition["aliases"])).compact.each do |key|
        symbol, string = key.to_s.to_sym, key.to_s
        return source[symbol] || source[string] if source.key?(symbol) || source.key?(string)
      end
      nil
    end

    def footprint_pin(item, definition, part)
      at = HoleId.parse(item[:at])
      return nil unless at.kind == :terminal
      pin_num = definition["num"].to_s
      if part.placement == "dip"
        count = part.data.dig("package", "pins").to_i
        count = part.pins.length if count.zero?
        half = count / 2
        first_row = at.row
        return invalid_placement(item, at) unless %w[e f].include?(first_row)
        row = first_row == "e" ? "e" : "f"
        col = at.col
        if pin_num.to_i <= half
          col += pin_num.to_i - 1 if first_row == "e"
          col -= pin_num.to_i - 1 if first_row == "f"
        else
          row = first_row == "e" ? "f" : "e"
          reverse_index = count - pin_num.to_i
          col += reverse_index
        end
        return "#{row}#{col}"
      end
      footprint = part.data["footprint"]
      return item[:at] unless footprint
      offset = footprint[pin_num]
      return item[:at] if !offset && pin_num == part.pins.first["num"].to_s
      return nil unless offset
      row_index = %w[a b c d e f g h i j].index(at.row)
      target_row = row_index && row_index + offset[1].to_i
      target_col = at.col + offset[0].to_i
      unless target_row&.between?(0, @board.height - 1) && target_col.between?(1, @board.width)
        @diagnostics << diagnostic(:invalid_placement, "#{item[:ref]} footprint extends beyond the board", item[:location], [item[:ref]])
        return nil
      end
      "#{%w[a b c d e f g h i j][target_row]}#{target_col}"
    rescue ArgumentError
      @diagnostics << diagnostic(:invalid_placement, "error", "invalid component anchor #{item[:at]}", item[:location], [item[:ref]])
      nil
    end

    def invalid_placement(item, at)
      unless @diagnostics.any? { |entry| entry.code == "invalid_placement" && entry.targets.include?(item[:ref]) }
        @diagnostics << diagnostic(:invalid_placement, "error", "DIP #{item[:ref]} must straddle the center gap (e/f row)", item[:location], [item[:ref], at.to_s])
      end
      nil
    end

    def resolve_wires(components)
      wires = []
      occupied = {}
      components.each_value do |component|
        component.pins.each_value do |pin|
          next unless pin.hole_id
          if occupied[pin.hole_id]
            @diagnostics << diagnostic(:hole_conflict, "hole #{pin.hole_id} is occupied by multiple leads", component.location,
                                       [component.ref, pin.hole_id])
          else
            occupied[pin.hole_id] = component.ref
          end
        end
      end
      @document.supplies.each do |item|
        [item[:plus], item[:minus]].each do |id|
          next unless @board.hole(id)
          if occupied[id]
            @diagnostics << diagnostic(:hole_conflict, "hole #{id} is already occupied", item[:location], [item[:name], id])
          else
            occupied[id] = item[:name]
          end
        end
      end
      reserved = {}
      @document.wires.each do |item|
        [item[:from], item[:to]].each do |endpoint|
          parsed = HoleId.parse(endpoint) rescue nil
          next unless parsed && (parsed.kind == :terminal || (parsed.kind == :rail && parsed.index))
          reserved[parsed.to_s] = true if @board.hole(parsed.to_s)
        end
      end
      ids = {}
      @document.wires.each_with_index do |item, index|
        wire_id = item[:id] || "W#{index + 1}"
        if ids[wire_id]
          @diagnostics << diagnostic(:duplicate_ref, "error", "duplicate wire ID #{wire_id}", item[:location], [wire_id])
          next
        end
        ids[wire_id] = true
        endpoints = [item[:from], item[:to]]
        parsed = endpoints.map { |endpoint| HoleId.parse(endpoint) rescue nil }
        endpoints.each_with_index do |endpoint, side|
          if parsed[side]&.kind == :pin
            pin_component, pin = component_pin(endpoint, components)
            next if pin_component&.part&.placement == "offboard" && pin
            pin_hole = endpoint_hole(endpoint, components)
            target_x = explicit_x(endpoints[1 - side], components)
            candidates = @board.strip(pin_hole)
            picked = candidates && candidates.map { |id| @board.hole(id) }
                                      .compact.reject { |hole| occupied[hole.id] || reserved[hole.id] }
                                      .min_by { |hole| [(target_x ? (hole.x - target_x).abs : 0), hole_order(hole)] }
            if picked
              endpoints[side], parsed[side] = picked.id, HoleId.parse(picked.id)
              occupied[picked.id] = wire_id
            else
              @diagnostics << diagnostic(:no_free_hole, "error", "no free hole in the strip for #{endpoint}", item[:location], [wire_id, endpoint])
            end
            next
          end
          next if parsed[side]&.kind == :terminal && @board.hole(endpoint)
          next if parsed[side]&.kind == :rail && parsed[side].index && @board.hole(endpoint)
          if parsed[side]&.kind == :rail && parsed[side].index.nil?
            target = explicit_x(endpoints[1 - side], components)
            picked = nearest_free(parsed[side].rail, target, occupied, reserved)
            if picked
              endpoints[side] = picked.id
              parsed[side] = HoleId.parse(picked.id)
              occupied[picked.id] = wire_id
            else
              @diagnostics << diagnostic(:no_free_hole, "error", "no free hole on rail #{parsed[side].rail}", item[:location], [wire_id])
            end
            next
          end
          @diagnostics << diagnostic(:invalid_hole, "error", "invalid or unknown wire endpoint #{endpoint.inspect}", item[:location], [wire_id, endpoint])
        end
        endpoints.each do |endpoint|
          id = endpoint_hole(endpoint, components)
          next unless id && @board.hole(id)
          if occupied[id] && occupied[id] != wire_id
            @diagnostics << diagnostic(:hole_conflict, "error", "hole #{id} is already occupied", item[:location], [wire_id, id])
          end
          occupied[id] = true
        end
        wires << Wire.new(id: wire_id, from: endpoints[0], to: endpoints[1], color: item[:color],
                          route: item[:route], location: item[:location])
      end
      wires
    end

    def explicit_x(endpoint, components)
      id = endpoint_hole(endpoint, components)
      @board.hole(id)&.x if id
    end

    def endpoint_hole(endpoint, components)
      id = HoleId.parse(endpoint)
      return id.to_s unless id.kind == :pin
      _component, pin = component_pin(endpoint, components)
      unless pin
        @diagnostics << diagnostic(:unknown_pin, "error", "unknown pin #{endpoint}", nil, [endpoint])
        return nil
      end
      pin.hole_id
    rescue ArgumentError
      nil
    end

    def component_pin(endpoint, components)
      id = HoleId.parse(endpoint)
      return [nil, nil] unless id.kind == :pin
      component = components[id.ref]
      pin = component && component.pins.values.find { |item| [item.name, item.number].include?(id.pin) }
      [component, pin]
    rescue ArgumentError
      [nil, nil]
    end

    def nearest_free(rail, target_x, occupied, reserved)
      candidates = @board.holes.values.select { |hole| hole.rail == rail && !occupied[hole.id] && !reserved[hole.id] }
      candidates.min_by { |hole| [(target_x ? (hole.x - target_x).abs : 0), hole.col] }
    end

    def hole_order(hole)
      [hole.x, hole.y]
    end

    def resolve_supplies
      @document.supplies.each do |item|
        [item[:plus], item[:minus]].each do |id|
          unless @board.hole(id)
            @diagnostics << diagnostic(:invalid_hole, "error", "invalid supply hole #{id}", item[:location], [item[:name], id])
          end
        end
      end
      @document.supplies.map do |item|
        Supply.new(name: item[:name], voltage: item[:voltage], plus: item[:plus], minus: item[:minus], location: item[:location])
      end
    end

    def validate_references(components, supplies, labels)
      labels.each { |label| validate_reference(label.at, label.location, components, supplies, labels) }
      @document.expectations.each do |expectation|
        entries = expectation[:entries] || expectation["entries"] || []
        entries.each do |entry|
          refs = entry[:refs] || entry["refs"] || []
          location = entry[:location] || entry["location"]
          Array(refs).each { |reference| validate_reference(reference, location, components, supplies, labels) }
        end
      end
    end

    def validate_reference(reference, location, components, supplies, labels)
      parsed = HoleId.parse(reference)
      case parsed.kind
      when :terminal, :rail
        @diagnostics << diagnostic(:invalid_hole, "error", "unknown hole #{reference}", location, [reference]) unless @board.hole(parsed.to_s)
      when :pin
        component = components[parsed.ref]
        if component
          valid = component.pins.values.any? { |pin| pin.name == parsed.pin || pin.number == parsed.pin }
          @diagnostics << diagnostic(:unknown_pin, "error", "unknown pin #{reference}", location, [reference]) unless valid
        elsif supplies.none? { |supply| supply.name == parsed.ref && %w[+ -].include?(parsed.pin) }
          @diagnostics << diagnostic(:unknown_pin, "error", "unknown pin or supply terminal #{reference}", location, [reference])
        end
      end
    rescue ArgumentError
      return if labels.any? { |label| label.name == reference.to_s }
      @diagnostics << diagnostic(:unknown_net, "error", "unknown net #{reference}", location, [reference])
    end

    def diagnostic(code, severity, message, location, targets = [])
      Diagnostic.new(code: code.to_s, severity: severity, message: message, location: location,
                     targets: Array(targets))
    end
  end
end
