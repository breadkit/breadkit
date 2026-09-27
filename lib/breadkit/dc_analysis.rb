# frozen_string_literal: true

require "matrix"

module Breadkit
  DCResult = Struct.new(:status, :voltages, :currents, :power, :floating, :reference_nodes,
                        :assumptions, :errors, keyword_init: true) do
    def success?
      status == :ok
    end
  end

  class Circuit
    def dc_analysis(state = nil)
      DCAnalysis.new(self).solve(state)
    end
  end

  # DC model: ideal voltage sources and switches, ohmic resistors, and fixed-drop diodes.
  # Capacitors are open at DC. Voltage in an ungrounded domain is relative to its
  # reported reference node; it has no absolute meaning against another domain.
  class DCAnalysis
    DIODE_MODELS = { "led" => [2.0, 1.0], "diode" => [0.7, 1.0] }.freeze
    MAX_ITERATIONS = 32

    def initialize(circuit)
      @circuit = circuit
    end

    def solve(state = nil)
      return failure(:invalid, "circuit has errors") if circuit.diagnostics.any? { |item| item.severity == "error" }

      @state = state
      @sources, @resistors, @diodes, unsupported = [], [], [], []
      ground_labels = Array(circuit.board.definition.data["ground_labels"] || %w[GND 0V VSS GROUND]).map(&:upcase)
      @ground_names = circuit.nets(state).select do |net|
        net.labels.any? { |label| ground_labels.include?(label.upcase) }
      end.map(&:name)
      collect_sources
      circuit.components.each_value { |component| collect_component(component, unsupported) }
      return failure(:unsupported, "no DC model for #{unsupported.join(', ')}") unless unsupported.empty?

      active = Array.new(@diodes.length, true)
      seen = {}
      MAX_ITERATIONS.times do
        key = active.join
        return failure(:nonconvergent, "diode states did not converge") if seen[key]

        seen[key] = true
        solved = solve_linear(active)
        return solved if solved.is_a?(DCResult)

        voltages, source_currents, references, floating = solved
        next_active = @diodes.map do |diode|
          anode, cathode, drop, resistance = diode.values_at(:anode, :cathode, :drop, :resistance)
          voltages.fetch(anode) - voltages.fetch(cathode) > drop - 1e-9 &&
            (voltages.fetch(anode) - voltages.fetch(cathode) - drop) / resistance >= -1e-9
        end
        if active == next_active
          if (bridge = unreturned_diode(active))
            return failure(:indeterminate, "#{bridge} has no return path; its DC bias is undefined")
          end

          currents = source_currents.dup
          power = {}
          @resistors.each do |resistor|
            current = resistor[:ohms].zero? ? source_currents.fetch(resistor[:name]) :
                      (voltages.fetch(resistor[:a]) - voltages.fetch(resistor[:b])) / resistor[:ohms]
            currents[resistor[:name]] = current
            power[resistor[:name]] = current * current * resistor[:ohms]
          end
          @diodes.each_with_index do |diode, index|
            current = active[index] ? (voltages.fetch(diode[:anode]) - voltages.fetch(diode[:cathode]) - diode[:drop]) / diode[:resistance] : 0.0
            currents[diode[:name]] = current
          end
          return DCResult.new(status: :ok, voltages: voltages, currents: currents, power: power,
                              floating: floating, reference_nodes: references, assumptions: assumptions, errors: [])
        end
        active = next_active
      end
      failure(:nonconvergent, "diode states did not converge")
    rescue ArgumentError, TypeError, KeyError => error
      failure(:invalid, error.message)
    end

    private

    attr_reader :circuit

    def failure(status, message)
      DCResult.new(status: status, voltages: {}, currents: {}, power: {}, floating: [],
                   reference_nodes: [], assumptions: assumptions, errors: [message])
    end

    def assumptions
      @sources.to_a.filter_map do |source|
        next unless source[:range]

        "#{source[:name]}: nominal #{source[:volts]} V from #{source[:range].join('..')} V range"
      end + @diodes.to_a.map do |diode|
        "#{diode[:name]}: fixed #{diode[:drop]} V forward drop, #{diode[:resistance]} Ω on resistance"
      end
    end

    def net_name(reference)
      circuit.net_of(reference, @state)&.name || (raise ArgumentError, "unresolved terminal #{reference}")
    end

    def collect_sources
      circuit.voltage_sources.each do |source|
        voltage = source.voltage.to_f
        raise ArgumentError, "invalid voltage source #{source.name}" unless voltage.finite? && voltage.positive?

        @sources << { name: source.name, a: net_name(source.plus), b: net_name(source.minus), volts: voltage,
                      range: source.voltage_range }
      end
    end

    def collect_component(component, unsupported)
      part = component.part
      case part.id
      when "resistor"
        value = Value.parse(component.value)
        raise ArgumentError, "invalid resistance #{component.ref}" unless value.finite? && value >= 0

        @resistors << { name: component.ref, a: net_name("#{component.ref}.1"), b: net_name("#{component.ref}.2"), ohms: value }
      when "led", "diode"
        default_drop, default_resistance = DIODE_MODELS.fetch(part.id)
        drop = part.data.fetch("forward_voltage", default_drop).to_f
        resistance = part.data.fetch("on_resistance", default_resistance).to_f
        polarity = part.data.fetch("polarity")
        @diodes << { name: component.ref, anode: net_name("#{component.ref}.#{polarity.fetch('positive')}"),
                     cathode: net_name("#{component.ref}.#{polarity.fetch('negative')}"),
                     drop: drop, resistance: resistance }
      when "capacitor", "electrolytic", "pin_header", "battery_box", "dc_jack_2wire"
        nil
      else
        return if part.data["switch"]
        if part.data["provides"]
          provided_outputs = Array(part.data["provides"]).filter_map { |source| part.pin(source["positive"]) }
          driven = component.pins.values.any? do |pin|
            definition = part.pin(pin.number)
            next unless %w[gpio output].include?(pin.role) || definition&.fetch("output_capable", false)
            next if provided_outputs.include?(definition)

            net = circuit.net_of("#{component.ref}.#{pin.name}", @state)
            net&.members&.any? { |member| member != "#{component.ref}.#{pin.name}" }
          end
          unsupported << "#{component.ref} output state" if driven
          return
        end

        unsupported << component.ref
      end
    end

    def solve_linear(active)
      nodes = (@sources.flat_map { |item| [item[:a], item[:b]] } +
               @resistors.flat_map { |item| [item[:a], item[:b]] } +
               @diodes.flat_map { |item| [item[:anode], item[:cathode]] }).uniq
      links = @sources.map { |item| [item[:a], item[:b]] } +
              @resistors.map { |item| [item[:a], item[:b]] } +
              @diodes.each_with_index.filter_map { |item, index| [item[:anode], item[:cathode]] if active[index] }
      groups = connected_groups(nodes, links)
      group_of = groups.each_with_index.each_with_object({}) { |(group, index), result| group.each { |node| result[node] = index } }
      @diodes.each_with_index do |diode, index|
        next if active[index] || group_of[diode[:anode]] == group_of[diode[:cathode]]

        return failure(:indeterminate, "#{diode[:name]} bridges independent DC domains while off")
      end
      references = groups.map { |group| reference_for(group) }
      floating = groups.reject { |group| group.any? { |name| ground?(name) } }
      variables = nodes - references
      index = variables.each_with_index.to_h
      ideal = @sources + @resistors.select { |item| item[:ohms].zero? }.map { |item| item.merge(volts: 0.0) }
      size = variables.length + ideal.length
      matrix = Array.new(size) { Array.new(size, 0.0) }
      rhs = Array.new(size, 0.0)
      @resistors.each { |item| stamp_conductance(matrix, index, item[:a], item[:b], 1.0 / item[:ohms]) unless item[:ohms].zero? }
      @diodes.each_with_index do |item, position|
        next unless active[position]

        conductance = 1.0 / item[:resistance]
        stamp_conductance(matrix, index, item[:anode], item[:cathode], conductance)
        rhs[index.fetch(item[:anode])] += conductance * item[:drop] if index.key?(item[:anode])
        rhs[index.fetch(item[:cathode])] -= conductance * item[:drop] if index.key?(item[:cathode])
      end
      ideal.each_with_index do |item, position|
        row = variables.length + position
        [[item[:a], 1.0], [item[:b], -1.0]].each do |node, sign|
          next unless index.key?(node)

          matrix[index.fetch(node)][row] += sign
          matrix[row][index.fetch(node)] += sign
        end
        rhs[row] = item[:volts]
      end
      solution = size.zero? ? [] : Matrix.rows(matrix).lup.solve(Vector.elements(rhs)).to_a
      return failure(:singular, "DC equations are inconsistent or underdetermined") unless valid_solution?(matrix, rhs, solution)

      voltages = nodes.to_h { |node| [node, index.key?(node) ? solution.fetch(index.fetch(node)) : 0.0] }
      currents = ideal.each_with_index.to_h { |item, position| [item[:name], solution.fetch(variables.length + position)] }
      [voltages, currents, references, floating]
    rescue ExceptionForMatrix::ErrNotRegular
      failure(:singular, "DC equations are inconsistent or underdetermined")
    end

    def stamp_conductance(matrix, index, a, b, conductance)
      return if a == b

      if index.key?(a)
        row = index.fetch(a)
        matrix[row][row] += conductance
        matrix[row][index.fetch(b)] -= conductance if index.key?(b)
      end
      if index.key?(b)
        row = index.fetch(b)
        matrix[row][row] += conductance
        matrix[row][index.fetch(a)] -= conductance if index.key?(a)
      end
    end

    def connected_groups(nodes, links)
      union = UnionFind.new
      nodes.each { |node| union.add(node) }
      links.each { |a, b| union.union(a, b) }
      nodes.group_by { |node| union.find(node) }.values
    end

    def unreturned_diode(active)
      base = @sources.map { |item| [item[:a], item[:b]] } + @resistors.map { |item| [item[:a], item[:b]] }
      @diodes.each_with_index do |diode, index|
        next unless active[index]

        union = UnionFind.new
        (base + @diodes.each_with_index.filter_map do |other, other_index|
          [other[:anode], other[:cathode]] if active[other_index] && other_index != index
        end).each { |a, b| union.union(a, b) }
        return diode[:name] unless union.find(diode[:anode]) == union.find(diode[:cathode])
      end
      nil
    end

    def reference_for(group)
      group.find { |name| ground?(name) } || @sources.lazy.map { |source| source[:b] }.find { |name| group.include?(name) } || group.first
    end

    def ground?(name)
      @ground_names.include?(name)
    end

    def valid_solution?(matrix, rhs, solution)
      return false unless solution.all?(&:finite?)

      matrix.each_with_index.all? do |row, index|
        result = row.zip(solution).sum { |coefficient, value| coefficient * value }
        (result - rhs.fetch(index)).abs <= 1e-7 * [rhs.fetch(index).abs, result.abs, 1.0].max
      end
    end
  end
end
