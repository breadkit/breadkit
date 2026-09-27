# frozen_string_literal: true

module Breadkit
  module Patterns
    module_function

    def call(circuit)
      return [] if circuit.diagnostics.any? { |item| item.severity == "error" }

      voltage_divider(circuit) + ne555_astable(circuit)
    end

    def voltage_divider(circuit)
      return [] if circuit.diagnostics.any? { |item| item.severity == "error" }
      return [] unless circuit.supplies.length == 1 && circuit.components.length == 2

      supply = circuit.supplies.first
      return [] if supply.voltage_range || !supply.voltage.to_f.positive?

      resistors = circuit.components.values
      return [] unless resistors.all? { |component| component.part.id == "resistor" &&
                                         component.pins.length == 2 && Value.parse(component.value).positive? }

      ends = resistors.map do |component|
        [1, 2].map { |pin| circuit.net_of("#{component.ref}.#{pin}")&.name }
      end
      return [] if ends.flatten.any?(&:nil?) || ends.any? { |pair| pair.uniq.length != 2 }

      plus = circuit.net_of(supply.plus)&.name
      minus = circuit.net_of(supply.minus)&.name
      shared = ends[0] & ends[1]
      return [] unless plus && minus && plus != minus && shared.length == 1

      midpoint = shared.first
      return [] if [plus, minus].include?(midpoint)

      top, bottom = resistors.zip(ends).partition { |_component, pair| pair.include?(plus) }
      return [] unless top.length == 1 && bottom.length == 1 && bottom.first[1].include?(minus)

      result = circuit.dc_analysis
      return [] unless result.success? && result.voltages.key?(midpoint) && result.voltages.key?(minus)

      voltage = result.voltages.fetch(midpoint) - result.voltages.fetch(minus)
      [{ "kind" => "voltage_divider", "supply" => supply.name,
         "top_resistor" => top.first[0].ref, "bottom_resistor" => bottom.first[0].ref,
         "midpoint_net" => midpoint, "midpoint_voltage_v" => voltage,
         "reference" => "#{supply.name}.-",
         "explanation" => "Two resistors form an unloaded voltage divider. The nominal midpoint voltage is relative to the supply negative terminal." }]
    rescue ArgumentError, TypeError
      []
    end

    def ne555_astable(circuit)
      return [] unless circuit.supplies.length == 1 && circuit.components.length == 8

      parts = circuit.components.values.group_by { |component| component.part.id }
      return [] unless %w[ne555 resistor capacitor electrolytic led].all? { |id| parts.key?(id) }
      return [] unless %w[ne555 resistor capacitor electrolytic led].map { |id| parts.fetch(id).length } == [1, 3, 2, 1, 1]

      timer = parts.fetch("ne555").first
      supply = circuit.supplies.first
      voltage = supply.voltage.to_f
      minimum, maximum = Array(timer.part.data["supply_range"])
      return [] unless supply.voltage_range.nil? && minimum && maximum && voltage.between?(minimum, maximum)

      plus = circuit.net_of(supply.plus)&.name
      minus = circuit.net_of(supply.minus)&.name
      pins = (1..8).to_h { |number| [number, terminal_net(circuit, timer, number)] }
      return [] if [plus, minus, *pins.values].any?(&:nil?)
      return [] unless pins[1] == minus && pins[4] == plus && pins[8] == plus && pins[2] == pins[6]

      discharge, timing, output, control = pins.values_at(7, 2, 3, 5)
      return [] unless [plus, minus, discharge, timing, output, control].uniq.length == 6

      led = parts.fetch("led").first
      led_anode = terminal_net(circuit, led, "anode")
      return [] unless terminal_net(circuit, led, "cathode") == minus && led_anode &&
                       ![plus, minus, discharge, timing, output, control].include?(led_anode)

      resistors = parts.fetch("resistor")
      capacitors = parts.fetch("capacitor") + parts.fetch("electrolytic")
      return [] unless (resistors + capacitors).all? { |part| Value.parse(part.value).positive? }

      charge = between(circuit, resistors, plus, discharge)
      discharge_resistor = between(circuit, resistors, discharge, timing)
      output_resistor = between(circuit, resistors, output, led_anode)
      control_capacitor = between(circuit, capacitors, control, minus)
      bypass_capacitor = between(circuit, capacitors, plus, minus)
      timing_capacitor = between(circuit, capacitors, timing, minus)
      return [] unless [charge, discharge_resistor, output_resistor, control_capacitor,
                        bypass_capacitor, timing_capacitor].all?
      return [] unless control_capacitor.part.id == "capacitor" && bypass_capacitor.part.id == "capacitor" &&
                       timing_capacitor.part.id == "electrolytic"
      return [] unless terminal_net(circuit, timing_capacitor, 1) == timing &&
                       terminal_net(circuit, timing_capacitor, 2) == minus

      [{ "kind" => "ne555_astable_wiring", "timer" => timer.ref, "supply" => supply.name,
         "charge_resistor" => charge.ref, "discharge_resistor" => discharge_resistor.ref,
         "timing_capacitor" => timing_capacitor.ref, "output_resistor" => output_resistor.ref,
         "output_led" => led.ref, "control_capacitor" => control_capacitor.ref,
         "bypass_capacitor" => bypass_capacitor.ref,
         "datasheet" => "https://www.ti.com/lit/ds/symlink/ne555.pdf",
         "explanation" => "This wiring matches the NE555 astable connection with an LED output load; this is not a simulation of oscillation or timing." }]
    rescue ArgumentError, TypeError
      []
    end

    def terminal_net(circuit, component, pin)
      circuit.net_of("#{component.ref}.#{pin}")&.name
    end

    def between(circuit, components, first, second)
      components.find do |component|
        ends = [1, 2].map { |pin| terminal_net(circuit, component, pin) }
        ends.all? && ends.sort == [first, second].sort
      end
    end
  end
end
