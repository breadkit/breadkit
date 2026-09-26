# frozen_string_literal: true

module Breadkit
  class Resolver
    def call(document)
      @document = document
      @diagnostics = []
      @board = load_board
      @terminal_positions = @board.holes.values.select { |hole| hole.kind == :terminal }.to_h { |hole| [[hole.x, hole.y], hole] }
      @library = PartLibrary.new(extra_paths: document.part_paths, extra_definitions: document.part_definitions)
      components = resolve_components
      wires = resolve_wires(components)
      supplies = resolve_supplies
      validate_names(components, wires, supplies)
      labels = document.labels.map { |item| Label.new(name: item[:name], at: item[:at], location: item[:location]) }
      validate_references(components, supplies, labels)
      circuit = Circuit.new(title: document.title, board: @board, components: components, wires: wires,
                            supplies: supplies, labels: labels, expectations: document.expectations,
                            lint_disables: document.lint_disables, diagnostics: @diagnostics)
      validate_split_labels(circuit) if labels.length > 1
      circuit
    end

    private

    def load_board
      Board.new(BoardDef.load(@document.board[:type], extra_paths: @document.board_paths,
                             extra_definitions: @document.board_definitions),
                split_rails: @document.board[:options][:split_rails] || false)
    rescue StandardError => e
      @diagnostics << diagnostic(:unknown_board, "error", e.message, nil)
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
        if item[:type].to_s == "transistor" && item[:value]
          model = @library.find(item[:value])
          if model && model.data["category"] == "transistor"
            part = model
          else
            @diagnostics << diagnostic(:unknown_transistor_model, "warning", "unknown transistor model #{item[:value]}; using generic EBC pinout", item[:location], [ref])
          end
        end
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
      if requested.is_a?(Hash)
        requested.each_key do |key|
          @diagnostics << diagnostic(:unknown_pin, "error", "unknown pin #{item[:ref]}.#{key}", item[:location], [item[:ref]]) unless part.pin(key)
        end
      end
      attrs = item[:attrs] || {}
      pin_names = part.pins.flat_map { |pin| [pin["num"], pin["name"], *Array(pin["aliases"])] }.compact.map(&:to_s)
      attrs.each_key do |key|
        next if part.pin(key) || %w[pin_count color layer address label side at].include?(key.to_s)

        suggestion = DidYouMean::SpellChecker.new(dictionary: pin_names).correct(key.to_s).first
        if suggestion
          @diagnostics << diagnostic(:unknown_pin, "error", "unknown pin #{item[:ref]}.#{key}; did you mean #{suggestion}?", item[:location], [item[:ref]])
        else
          @diagnostics << diagnostic(:unknown_option, "error", "unknown component option #{item[:ref]}.#{key}", item[:location], [item[:ref]])
        end
      end
      if item[:at] && part.placement == "leads"
        placement_error(item, "#{part.id} has no footprint; place its pins explicitly")
      end
      part.pins.each_with_index do |definition, index|
        name, number = definition["name"] || definition["num"].to_s, definition["num"].to_s
        anchor = explicit_pin(requested, definition, index)
        anchor ||= explicit_pin(item[:attrs], definition, index)
        if anchor.nil? && item[:at] && part.placement != "leads"
          anchor = footprint_pin(item, definition, part)
        end
        if anchor
          hole = @board.hole(anchor)
          unless hole
            if part.placement == "dip"
              placement_error(item, "DIP #{item[:ref]} extends beyond the board")
            else
              @diagnostics << diagnostic(:invalid_hole, "error", "invalid hole #{anchor.inspect}", item[:location], [item[:ref], anchor])
            end
          end
          result[name.to_s] = Pin.new(name: name.to_s, number: number, hole_id: hole&.id,
                                      node_id: "pin:#{item[:ref]}.#{name}", role: definition["type"] || definition["role"])
        else
          result[name.to_s] = Pin.new(name: name.to_s, number: number, node_id: "pin:#{item[:ref]}.#{name}",
                                      role: definition["type"] || definition["role"])
        end
      end
      validate_footprint_geometry(item, part, result) if requested && part.placement == "footprint"
      if part.data["straddle"] && (item[:at] || requested)
        groups = @board.definition.data.dig("terminal", "groups")
        occupied_groups = result.values.filter_map do |pin|
          row = @board.hole(pin.hole_id)&.row
          groups&.index { |rows| rows.include?(row) } if row
        end.uniq
        placement_error(item, "#{item[:ref]} must straddle the center gap") if occupied_groups.length < 2
      end
      placement_requested = requested || item[:at] || attrs.keys.any? { |key| part.pin(key) }
      if placement_requested && part.placement != "offboard" && !@diagnostics.any? { |entry| entry.code == "invalid_placement" && entry.targets.include?(item[:ref]) }
        missing = result.values.reject(&:hole_id).map(&:name)
        @diagnostics << diagnostic(:unplaced_pin, "error", "#{item[:ref]} has unplaced pins: #{missing.join(', ')}", item[:location], [item[:ref]]) unless missing.empty?
      end
      result
    end

    def explicit_pin(source, definition, index)
      return nil unless source
      if source.is_a?(Array)
        return source[index]
      end
      return nil unless source.respond_to?(:each_pair)
      names = ([definition["num"], definition["name"]] + Array(definition["aliases"])).compact.map { |key| key.to_s.downcase }
      source.each_pair.find { |key, _value| names.include?(key.to_s.downcase) }&.last
    end

    def validate_footprint_geometry(item, part, result)
      footprint = part.data["footprint"]
      return unless footprint

      first = part.pins.first
      first_key = (first["name"] || first["num"]).to_s
      origin = @board.hole(item[:at] || result[first_key]&.hole_id)
      return unless origin

      first_offset = footprint[first["num"].to_s] || [0, 0]
      part.pins.each do |definition|
        pin = result[(definition["name"] || definition["num"]).to_s]
        next unless pin&.hole_id

        offset = footprint[definition["num"].to_s]
        next unless offset

        expected = @terminal_positions[[origin.x + offset[0].to_i - first_offset[0].to_i,
                                         origin.y + offset[1].to_i - first_offset[1].to_i]]
        unless pin.hole_id == expected&.id
          placement_error(item, "#{item[:ref]} pins do not match its footprint")
          break
        end
      end
    end

    def footprint_pin(item, definition, part)
      at = HoleId.parse(item[:at], board: @board)
      unless at.kind == :terminal
        placement_error(item, "#{item[:ref]} needs a terminal hole anchor")
        return nil
      end
      pin_num = definition["num"].to_s
      if part.placement == "dip"
        count = part.data.dig("package", "pins").to_i
        count = part.pins.length if count.zero?
        half = count / 2
        first_row = at.row
        near_row, far_row = @board.ravine_between
        return invalid_placement(item, at) unless [near_row, far_row].include?(first_row)
        row = first_row
        col = at.col
        if pin_num.to_i <= half
          col += pin_num.to_i - 1 if first_row == near_row
          col -= pin_num.to_i - 1 if first_row == far_row
        else
          row = first_row == near_row ? far_row : near_row
          reverse_index = count - pin_num.to_i
          col += first_row == near_row ? reverse_index : -reverse_index
        end
        return "#{row}#{col}"
      end
      footprint = part.data["footprint"]
      return nil unless footprint
      offset = footprint[pin_num]
      return item[:at] if !offset && pin_num == part.pins.first["num"].to_s
      return nil unless offset
      anchor = @board.hole(at.to_s)
      target = anchor && @terminal_positions[[anchor.x + offset[0].to_i, anchor.y + offset[1].to_i]]
      unless target
        placement_error(item, "#{item[:ref]} footprint extends beyond the board or into the center gap")
        return nil
      end
      target.id
    rescue ArgumentError
      placement_error(item, "invalid component anchor #{item[:at]}")
      nil
    end

    def placement_error(item, message)
      return if @diagnostics.any? { |entry| entry.code == "invalid_placement" && entry.targets.include?(item[:ref]) }

      @diagnostics << diagnostic(:invalid_placement, "error", message, item[:location], [item[:ref]])
    end

    def invalid_placement(item, at)
      unless @diagnostics.any? { |entry| entry.code == "invalid_placement" && entry.targets.include?(item[:ref]) }
        @diagnostics << diagnostic(:invalid_placement, "error", "DIP #{item[:ref]} must straddle the center gap (#{@board.ravine_between.join('/')} row)", item[:location], [item[:ref], at.to_s])
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
            @diagnostics << diagnostic(:hole_conflict, "error", "hole #{pin.hole_id} is occupied by multiple leads", component.location,
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
            @diagnostics << diagnostic(:hole_conflict, "error", "hole #{id} is already occupied", item[:location], [item[:name], id])
          else
            occupied[id] = item[:name]
          end
        end
      end
      reserved = {}
      @document.wires.each do |item|
        next if item[:electrical] == false

        [item[:from], item[:to]].each do |endpoint|
          parsed = HoleId.parse(endpoint, board: @board) rescue nil
          next unless parsed && (parsed.kind == :terminal || (parsed.kind == :rail && parsed.index))
          reserved[parsed.to_s] = true if @board.hole(parsed.to_s)
        end
      end
      ids = {}
      reserved_ids = components.keys + @document.supplies.map { |item| item[:name] } + @document.wires.filter_map { |item| item[:id] }
      next_id = 1
      @document.wires.each do |item|
        unless item[:id]
          next_id += 1 while reserved_ids.include?("W#{next_id}") || ids["W#{next_id}"]
        end
        wire_id = item[:id] || "W#{next_id}"
        next_id += 1 unless item[:id]
        if ids[wire_id]
          @diagnostics << diagnostic(:duplicate_ref, "error", "duplicate wire ID #{wire_id}", item[:location], [wire_id])
          next
        end
        ids[wire_id] = true
        endpoints = [item[:from], item[:to]]
        if item[:electrical] == false
          endpoints.each do |endpoint|
            parsed = HoleId.parse(endpoint, board: @board) rescue nil
            valid = if parsed&.kind == :pin
              pin_component, pin = component_pin(endpoint, components)
              unless pin
                @diagnostics << diagnostic(:unknown_pin, "error", "unknown pin #{endpoint}", item[:location], [wire_id, endpoint])
                next
              end
              pin && (pin.hole_id || pin_component&.part&.placement == "offboard")
            else
              parsed && @board.hole(parsed.to_s)
            end
            @diagnostics << diagnostic(:invalid_hole, "error", "invalid visual wire endpoint #{endpoint.inspect}", item[:location], [wire_id, endpoint]) unless valid
          end
          wires << Wire.new(id: wire_id, from: endpoints[0], to: endpoints[1], color: item[:color],
                            route: item[:route], layer: item[:layer], electrical: false, dashed: item[:dashed],
                            location: item[:location])
          next
        end
        parsed = endpoints.map { |endpoint| HoleId.parse(endpoint, board: @board) rescue nil }
        endpoints.each_with_index do |endpoint, side|
          if parsed[side]&.kind == :pin
            pin_component, pin = component_pin(endpoint, components)
            unless pin
              @diagnostics << diagnostic(:unknown_pin, "error", "unknown pin #{endpoint}", item[:location], [wire_id, endpoint])
              next
            end
            next if pin_component&.part&.placement == "offboard" && pin
            pin_hole = endpoint_hole(endpoint, components)
            target_x = explicit_x(endpoints[1 - side], components)
            candidates = @board.strip(pin_hole)
            picked = candidates && candidates.map { |id| @board.hole(id) }
                                      .compact.reject { |hole| occupied[hole.id] || reserved[hole.id] }
                                      .min_by { |hole| [(target_x ? (hole.x - target_x).abs : 0), hole_order(hole)] }
            if picked
              endpoints[side], parsed[side] = picked.id, HoleId.parse(picked.id, board: @board)
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
              parsed[side] = HoleId.parse(picked.id, board: @board)
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
                          route: item[:route], layer: item[:layer], electrical: true, dashed: item[:dashed],
                          location: item[:location])
      end
      wires
    end

    def explicit_x(endpoint, components)
      id = endpoint_hole(endpoint, components)
      @board.hole(id)&.x if id
    end

    def endpoint_hole(endpoint, components)
      id = HoleId.parse(endpoint, board: @board)
      return id.to_s unless id.kind == :pin
      _component, pin = component_pin(endpoint, components)
      pin&.hole_id
    rescue ArgumentError
      nil
    end

    def component_pin(endpoint, components)
      id = HoleId.parse(endpoint, board: @board)
      return [nil, nil] unless id.kind == :pin
      component = components[id.ref]
      pin = component&.pin(id.pin)
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

    def validate_names(components, wires, supplies)
      names = {}
      entries = components.values.map { |item| [item.ref, item.location] } +
                wires.map { |item| [item.id, item.location] } +
                supplies.map { |item| [item.name, item.location] }
      entries.each do |name, location|
        if names[name]
          @diagnostics << diagnostic(:duplicate_ref, "error", "duplicate name #{name}", location, [name])
        else
          names[name] = true
        end
      end
    end

    def validate_split_labels(circuit)
      by_name = Hash.new { |hash, name| hash[name] = [] }
      circuit.nets.each { |net| net.labels.each { |name| by_name[name] << net } }
      by_name.each do |name, nets|
        next if nets.length < 2

        label = circuit.labels.find { |item| item.name == name }
        @diagnostics << diagnostic(:split_net_label, "error", "label #{name} is used on disconnected nets", label.location,
                                   [name, *nets.map(&:name)])
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
      parsed = HoleId.parse(reference, board: @board)
      case parsed.kind
      when :terminal, :rail
        @diagnostics << diagnostic(:invalid_hole, "error", "unknown hole #{reference}", location, [reference]) unless @board.hole(parsed.to_s)
      when :pin
        component = components[parsed.ref]
        if component
          valid = component.pin(parsed.pin)
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
