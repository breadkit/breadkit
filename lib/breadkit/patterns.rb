# frozen_string_literal: true

module Breadkit
  module Patterns
    module_function

    def call(circuit)
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
  end
end
