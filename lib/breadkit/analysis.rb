# frozen_string_literal: true

module Breadkit
  State = Struct.new(:name, :closed_switches, keyword_init: true)
  PotentialResult = Struct.new(:values, :conflicts, :components, keyword_init: true)

  class UnionFind
    def initialize
      @parent, @rank = {}, {}
    end

    def add(item)
      @parent[item] ||= item
    end

    def find(item)
      add(item)
      @parent[item] = find(@parent[item]) unless @parent[item] == item
      @parent[item]
    end

    def union(a, b)
      left, right = find(a), find(b)
      return if left == right
      @rank[left] ||= 0
      @rank[right] ||= 0
      left, right = right, left if @rank[left] < @rank[right]
      @parent[right] = left
      @rank[left] += 1 if @rank[left] == @rank[right]
    end
  end

  class Circuit
    attr_reader :title, :board, :components, :wires, :supplies, :labels, :expectations,
                :lint_disables, :diagnostics

    def initialize(title:, board:, components:, wires:, supplies:, labels:, expectations:, lint_disables:, diagnostics:)
      @title, @board, @components, @wires, @supplies, @labels = title, board, components, wires, supplies, labels
      @expectations, @lint_disables, @diagnostics = expectations, lint_disables, diagnostics
      @net_cache, @net_index, @potential_cache = {}, {}, {}
    end

    def states(mode = "single")
      switches = components.values.select { |component| !Array(component.part.data["switch"]).empty? }
      return [State.new(name: nil, closed_switches: [])] if mode.to_s == "none" || switches.empty?
      # ponytail: exhaustive state generation stops at 8 switches; use a configurable search budget for larger circuits.
      if mode.to_s == "all" && switches.length <= 8
        (0...(1 << switches.length)).map do |bits|
          selected = switches.each_with_index.filter_map { |component, index| component if bits[index] == 1 }
          closed = selected.flat_map { |component| Array(component.part.data["switch"]).map { |pair| [component, pair] } }
          State.new(name: selected.empty? ? nil : selected.map(&:ref).join(","), closed_switches: closed)
        end
      else
        singles = switches.map do |component|
          pairs = Array(component.part.data["switch"]).map { |pair| [component, pair] }
          State.new(name: component.ref, closed_switches: pairs)
        end
        all_pairs = singles.flat_map(&:closed_switches)
        singles << State.new(name: switches.map(&:ref).join(","), closed_switches: all_pairs) if mode.to_s == "all"
        [State.new(name: nil, closed_switches: [])] + singles
      end
    end

    def nets(state = nil)
      state ||= State.new(name: nil, closed_switches: [])
      key = state_key(state)
      return @net_cache[key] if @net_cache.key?(key)

      resolved = Connectivity.new(self).build(state)
      @net_index[key] = resolved.each_with_object({}) do |net, index|
        index[net.name] ||= net
        net.members.each do |member|
          index[member] ||= net
          node = node_for_reference(member)
          index[node] ||= net if node
        end
        net.labels.each { |label| index[label] ||= net }
        net.holes.each { |hole| index["hole:#{hole}"] ||= net }
      end
      @net_cache[key] = resolved
      result = PotentialSolver.new(self).solve(state)
      @potential_cache[key] = result
      resolved.each { |net| net.potential = result.values[net.name] }
      resolved
    end

    def potentials(state = nil)
      state ||= State.new(name: nil, closed_switches: [])
      nets(state)
      @potential_cache.fetch(state_key(state))
    end

    def net_of(reference, state = nil)
      text = reference.to_s
      nets(state)
      index = @net_index[state_key(state || State.new(name: nil, closed_switches: []))]
      index[text] || index[node_for_reference(text)]
    end

    def to_ir
      IR::Writer.new.write(self)
    end

    def shortest_path(terminal_a, terminal_b, state = nil)
      start, finish = hole_for_reference(terminal_a.to_s), hole_for_reference(terminal_b.to_s)
      return [] unless start && finish
      adjacency = Hash.new { |hash, key| hash[key] = [] }
      board.strips.each_value do |ids|
        # ponytail: each strip is a small clique; use virtual strip nodes if custom boards make this quadratic cost large.
        ids.combination(2) { |left, right| adjacency[left] << [right, nil]; adjacency[right] << [left, nil] }
      end
      wires.each do |wire|
        next if wire.electrical == false

        left, right = hole_for_reference(wire.from), hole_for_reference(wire.to)
        next unless left && right
        adjacency[left] << [right, wire.id]
        adjacency[right] << [left, wire.id]
      end
      components.each_value do |component|
        Array(component.part.data["internal"]).each do |pair|
          join_physical_pins(adjacency, component, pair)
        end
      end
      (state || State.new(name: nil, closed_switches: [])).closed_switches.each do |component, pair|
        join_physical_pins(adjacency, component, pair)
      end
      previous, queue = { start => nil }, [start]
      until queue.empty? || previous.key?(finish)
        current = queue.shift
        adjacency[current].each do |neighbor, edge|
          next if previous.key?(neighbor)
          previous[neighbor] = [current, edge]
          queue << neighbor
        end
      end
      return [terminal_a.to_s, terminal_b.to_s] unless previous.key?(finish)
      path, current = [], finish
      while (entry = previous[current])
        parent, edge = entry
        path << current
        path << edge if edge
        current = parent
      end
      (path << start).reverse.map { |item| item.start_with?("pin:") ? item.delete_prefix("pin:") : item }
    end

    def node_for_reference(reference)
      if reference.include?(".")
        prefix, pin = reference.split(".", 2)
        if components[prefix]
          item = components[prefix].pin(pin)
          return item&.node_id
        end
        supply = supplies.find { |item| item.name == prefix }
        return "supply:#{reference}" if supply && %w[+ -].include?(pin)
      end
      return "hole:#{board.hole(reference).id}" if board.hole(reference)
      "label:#{reference}" if labels.any? { |item| item.name == reference }
    rescue ArgumentError
      nil
    end

    private

    def hole_for_reference(reference)
      if reference.include?(".")
        prefix, pin = reference.split(".", 2)
        supply = supplies.find { |item| item.name == prefix }
        return supply.plus if supply && pin == "+"
        return supply.minus if supply && pin == "-"
        component = components[prefix]
        target = component&.pin(pin)
        return target&.hole_id || target&.node_id
      end
      board.hole(reference)&.id
    rescue ArgumentError
      nil
    end

    def join_physical_pins(adjacency, component, pair)
      left = component.pin(pair[0])
      right = component.pin(pair[1])
      return unless left && right
      left_node, right_node = left.hole_id || left.node_id, right.hole_id || right.node_id
      adjacency[left_node] << [right_node, component.ref]
      adjacency[right_node] << [left_node, component.ref]
    end

    def state_key(state)
      state.closed_switches.map { |component, pair| [component.ref, pair] }.sort_by(&:to_s)
    end
  end

  class Connectivity
    def initialize(circuit)
      @circuit = circuit
    end

    def build(state)
      @uf = UnionFind.new
      circuit.board.strips.each_value { |ids| ids.each_cons(2) { |a, b| @uf.union(hole_node(a), hole_node(b)) } }
      circuit.components.each_value do |component|
        component.pins.each_value { |pin| @uf.union(pin.node_id, hole_node(pin.hole_id)) if pin.hole_id }
        Array(component.part.data["internal"]).each { |pair| join_pins(component, pair) }
      end
      circuit.wires.each do |wire|
        next if wire.electrical == false

        id = wire_node(wire.id)
        @uf.union(id, endpoint_node(wire.from))
        @uf.union(id, endpoint_node(wire.to))
      end
      circuit.supplies.each do |supply|
        @uf.union(supply_node(supply.name, "+"), hole_node(supply.plus))
        @uf.union(supply_node(supply.name, "-"), hole_node(supply.minus))
      end
      state.closed_switches.each { |component, pair| join_pins(component, pair) }

      groups = Hash.new { |hash, key| hash[key] = { members: [], holes: [], labels: [], supplies: [] } }
      exposed_nodes.each do |node, member, kind|
        entry = groups[@uf.find(node)]
        entry[:members] << member if member
        entry[:holes] << node.delete_prefix("hole:") if kind == :hole
        entry[:supplies] << member if kind == :supply
      end
      circuit.labels.each do |label|
        node = endpoint_node(label.at)
        groups[@uf.find(node)][:labels] << label if node
      end
      roots = groups.keys.select { |root| !groups[root][:members].empty? || !groups[root][:labels].empty? }
                   .sort_by { |root| order_for(groups[root][:holes]) }
      used_names = {}
      roots.map.with_index do |root, index|
        data = groups[root]
        chosen = data[:labels].first&.name || supply_name(data[:supplies])
        chosen ||= "N#{roots.take(index + 1).count { |candidate| groups[candidate][:labels].empty? && groups[candidate][:supplies].empty? }}"
        name = chosen
        if used_names[name]
          # Multiple nets can have the same label; retain deterministic unique display names.
          name = "#{chosen}_#{index + 1}"
        end
        used_names[name] = true
        net = Net.new(name: name, members: data[:members].uniq, holes: data[:holes].uniq.sort_by { |id| hole_order(id) },
                      labels: data[:labels].map(&:name).uniq)
        net.instance_variable_set(:@root, root)
        net
      end
    end

    private

    attr_reader :circuit

    def exposed_nodes
      list = []
      circuit.board.holes.each_key { |id| list << [hole_node(id), nil, :hole] }
      circuit.components.each_value do |component|
        component.pins.each_value { |pin| list << [pin.node_id, "#{component.ref}.#{pin.name}", :pin] }
      end
      circuit.wires.each { |wire| list << [wire_node(wire.id), wire.id, :wire] unless wire.electrical == false }
      circuit.supplies.each do |supply|
        list << [supply_node(supply.name, "+"), "#{supply.name}.+", :supply]
        list << [supply_node(supply.name, "-"), "#{supply.name}.-", :supply]
      end
      circuit.labels.each do |label|
        node = endpoint_node(label.at)
        list << [node, nil, :label] if node
      end
      list
    end

    def endpoint_node(value)
      parsed = HoleId.parse(value, board: circuit.board)
      if parsed.kind == :pin
        component = circuit.components[parsed.ref]
        pin = component&.pin(parsed.pin)
        return pin.node_id if pin
        supply = circuit.supplies.find { |item| item.name == parsed.ref }
        return supply_node(parsed.ref, parsed.pin) if supply && %w[+ -].include?(parsed.pin)
        return nil
      end
      hole_node(parsed.to_s)
    rescue ArgumentError
      nil
    end

    def join_pins(component, pair)
      left = component.pin(pair[0])
      right = component.pin(pair[1])
      @uf.union(left.node_id, right.node_id) if left && right
    end

    def hole_node(id)
      "hole:#{id}"
    end

    def wire_node(id)
      "wire:#{id}"
    end

    def supply_node(name, side)
      "supply:#{name}.#{side}"
    end

    def order_for(holes)
      holes.map { |id| hole_order(id) }.min || [Float::INFINITY, Float::INFINITY]
    end

    def hole_order(id)
      hole = circuit.board.hole(id)
      hole ? [hole.x, hole.y] : [Float::INFINITY, Float::INFINITY]
    end

    def supply_name(members)
      members.first&.sub(/\.(?=[+-]\z)/, "")
    end
  end

  class PotentialSolver
    def initialize(circuit)
      @circuit = circuit
    end

    def solve(state)
      edges = circuit.supplies.map do |supply|
        [supply, circuit.net_of("#{supply.name}.-", state), circuit.net_of("#{supply.name}.+", state)]
      end
      values, conflicts = {}, []
      adjacency = Hash.new { |hash, key| hash[key] = [] }
      edges.each do |supply, from, to|
        next unless from && to
        adjacency[from.name] << [supply, to.name, supply.voltage, "#{supply.name}.+"]
        adjacency[to.name] << [supply, from.name, -supply.voltage, "#{supply.name}.-"]
      end
      ground = circuit.nets(state).find { |net| net.labels.include?("GND") }&.name
      components, witnesses, seen_conflicts = [], {}, {}
      starts = adjacency.keys
      starts = [ground, *(starts - [ground])] if starts.include?(ground)
      starts.each do |start|
        next if values.key?(start)
        components << start
        values[start] = 0.0
        witnesses[start] = edges.lazy.filter_map do |supply, from, to|
          if from&.name == start
            "#{supply.name}.-"
          elsif to&.name == start
            "#{supply.name}.+"
          end
        end.first
        queue = [start]
        until queue.empty?
          current = queue.shift
          adjacency[current].each do |supply, target, delta, terminal|
            proposed = values[current] + delta
            if values.key?(target)
              next if (values[target] - proposed).abs <= 1e-9 || seen_conflicts[supply.name]

              first, second = witnesses[target], terminal
              path = circuit.shortest_path(first, second, state)
              path_wires = circuit.wires.select { |wire| path.include?(wire.id) }
              conflicts << { supply: supply, net: target, expected: values[target], actual: proposed,
                             terminal_a: first, terminal_b: second, path: path,
                             wires: path_wires.map(&:id), location: path_wires.max_by { |wire| wire.location&.line.to_i }&.location || supply.location }
              seen_conflicts[supply.name] = true
            else
              values[target] = proposed
              witnesses[target] = terminal
              queue << target
            end
          end
        end
      end
      values[ground] = 0.0 if ground && !values.key?(ground)
      PotentialResult.new(values: values, conflicts: conflicts, components: components)
    end

    private

    attr_reader :circuit
  end
end
