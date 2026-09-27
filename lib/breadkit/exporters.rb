# frozen_string_literal: true

require "cgi/escape"

module Breadkit
  module Exporters
    FORMATS = %w[kicad spice wokwi pins fritzing].freeze

    module_function

    def call(circuit, format:)
      errors = circuit.diagnostics.select { |item| item.severity == "error" }
      raise ArgumentError, "cannot export a circuit with errors: #{errors.first.message}" unless errors.empty?

      case format.to_s
      when "kicad" then kicad(circuit)
      when "spice" then spice(circuit)
      when "wokwi" then JSON.pretty_generate(wokwi(circuit))
      when "pins" then pins(circuit)
      when "fritzing" then FritzingExport.call(circuit)
      else raise ArgumentError, "unknown export format #{format}; choose #{FORMATS.join(', ')}"
      end
    end

    def kicad(circuit)
      components = circuit.components.values.map do |component|
        %(    <comp ref="#{xml(component.ref)}"><value>#{xml(component.value || component.part.id)}</value>) +
          %(<libsource lib="breadkit" part="#{xml(component.part.id)}"/></comp>)
      end
      components.concat(circuit.supplies.map do |supply|
        %(    <comp ref="#{xml(supply.name)}"><value>#{xml(supply.voltage)}V</value>) +
          %(<libsource lib="breadkit" part="supply"/></comp>)
      end)
      definitions = circuit.components.values.map(&:part).uniq.map do |part|
        pin_type = %w[resistor capacitor electrolytic led diode].include?(part.id) ? "passive" : "unspecified"
        pins = part.pins.map do |pin|
          %(      <pin num="#{xml(pin.fetch('num'))}" name="#{xml(pin['name'] || pin['num'])}" type="#{pin_type}"/>)
        end
        %(    <libpart lib="breadkit" part="#{xml(part.id)}">\n      <pins>\n#{pins.join("\n")}\n      </pins>\n    </libpart>)
      end
      if circuit.supplies.any?
        definitions << %(    <libpart lib="breadkit" part="supply"><pins>) +
                       %(<pin num="1" name="+" type="power_out"/>) +
                       %(<pin num="2" name="-" type="power_out"/>) +
                       %(</pins></libpart>)
      end
      nets = circuit.nets.filter_map.with_index(1) do |net, code|
        nodes = net.members.filter_map do |member|
          ref, name = member.split(".", 2)
          if circuit.components[ref]
            pin = circuit.components[ref].pin(name)
            %(      <node ref="#{xml(ref)}" pin="#{xml(pin.number)}"/>) if pin
          elsif circuit.supplies.any? { |supply| supply.name == ref } && %w[+ -].include?(name)
            %(      <node ref="#{xml(ref)}" pin="#{name == '+' ? 1 : 2}"/>)
          end
        end
        next if nodes.empty? || (nodes.length == 1 && net.labels.empty?)

        %(    <net code="#{code}" name="#{xml(net.name)}">\n#{nodes.uniq.join("\n")}\n    </net>)
      end
      <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <export version="E">
          <design><source>breadkit</source><tool>breadkit</tool></design>
          <components>
        #{components.join("\n")}
          </components>
          <libparts>
        #{definitions.join("\n")}
          </libparts>
          <nets>
        #{nets.join("\n")}
          </nets>
        </export>
      XML
    end

    def spice(circuit)
      unsupported = circuit.components.values.reject { |item| %w[resistor capacitor].include?(item.part.id) }
      raise ArgumentError, "SPICE export supports only resistors and capacitors: #{unsupported.map(&:ref).join(', ')}" unless unsupported.empty?
      raise ArgumentError, "SPICE export needs a supply to establish ground" if circuit.supplies.empty?
      if circuit.supplies.any? { |item| item.voltage_range || !item.voltage.is_a?(Numeric) }
        raise ArgumentError, "SPICE export requires fixed supply voltages"
      end

      ground = circuit.net_of("#{circuit.supplies.first.name}.-")
      raise ArgumentError, "SPICE export cannot find the ground net" unless ground
      names = circuit.nets.each_with_index.to_h { |net, index| [net.name, net == ground ? "0" : "N#{index + 1}"] }
      lines = ["Breadkit circuit"]
      circuit.supplies.each do |supply|
        safe_identifier!(supply.name, "supply")
        lines << "V#{supply.name} #{spice_node(circuit, names, "#{supply.name}.+")} #{spice_node(circuit, names, "#{supply.name}.-")} #{number(supply.voltage)}"
      end
      circuit.components.each_value do |component|
        prefix = component.part.id == "resistor" ? "R" : "C"
        safe_identifier!(component.ref, "component")
        raise ArgumentError, "#{component.ref} must start with #{prefix} for SPICE" unless component.ref.start_with?(prefix)
        pin_names = component.part.pins.map { |pin| (pin["name"] || pin["num"]).to_s }
        raise ArgumentError, "#{component.ref} must have two pins" unless pin_names.length == 2
        value = Value.parse(component.value)
        raise ArgumentError, "#{component.ref} needs a positive value" unless value.positive? && value.finite?
        nodes = pin_names.map { |pin| spice_node(circuit, names, "#{component.ref}.#{pin}") }
        lines << "#{component.ref} #{nodes.join(' ')} #{number(value)}"
      end
      (lines + [".op", ".end", ""]).join("\n")
    end

    def wokwi(circuit)
      raise ArgumentError, "Wokwi export requires an offboard controller, not standalone supplies" unless circuit.supplies.empty?
      types = { "resistor" => "wokwi-resistor", "led" => "wokwi-led", "arduino_uno" => "wokwi-arduino-uno" }
      parts = circuit.components.values.each_with_index.map do |component, index|
        type = types[component.part.id]
        raise ArgumentError, "Wokwi export does not support #{component.part.id} (#{component.ref})" unless type

        attrs = case component.part.id
        when "resistor" then { value: number(Value.parse(component.value)) }
        when "led" then { color: component.attrs.fetch(:color, "red").to_s }
        else {}
        end
        { id: component.ref, type: type, left: index * 180, top: 0, attrs: attrs }
      end
      active = circuit.components.values.flat_map do |component|
        component.pins.values.filter_map { |pin| "#{component.ref}.#{pin.name}" if pin.hole_id }
      end
      active.concat(circuit.wires.flat_map { |wire| [wire.from, wire.to].select { |end_at| end_at.include?(".") } })
      active.uniq!
      connections = circuit.nets.flat_map do |net|
        color = circuit.wires.find { |wire| wire.electrical != false && net.members.include?(wire.id) }&.color || "green"
        endpoints = net.members.filter_map do |member|
          next unless active.include?(member)
          ref, pin_name = member.split(".", 2)
          component = circuit.components[ref]
          next unless component
          mapped = wokwi_pin(component, pin_name)
          raise ArgumentError, "Wokwi has no pin for #{member}" unless mapped
          "#{ref}:#{mapped}"
        end.uniq
        endpoints.drop(1).map { |other| [endpoints.first, other, color, []] }
      end
      { version: 1, author: "Breadkit", editor: "wokwi", parts: parts, connections: connections }
    end

    def pins(circuit)
      controllers = circuit.components.values.select { |item| %w[arduino_uno arduino_nano pico pico_w rp2040_clone].include?(item.part.id) }
      raise ArgumentError, "pin export needs exactly one Arduino Uno, Nano, or RP2040 controller" unless controllers.length == 1
      controller = controllers.first
      arduino = %w[arduino_uno arduino_nano].include?(controller.part.id)
      declarations = {}
      controller.pins.each_value do |pin|
        number = if arduino
          pin.name[/\A(?:D(\d+)|(A\d+))\z/, 1] || pin.name[/\A(A\d+)\z/, 1]
        else
          pin.name[/\AGP(\d+)\z/, 1]
        end
        next unless number
        net = circuit.net_of("#{controller.ref}.#{pin.name}")
        next unless net
        peers = net.members.grep(/\A(?!#{Regexp.escape(controller.ref)}\.)[^.]+\.[^.]+\z/)
        next if peers.empty? && net.labels.empty?

        name = net.labels.first || peers.first || net.name
        constant = "PIN_#{name.upcase.gsub(/[^A-Z0-9]+/, '_').sub(/_\z/, '')}"
        raise ArgumentError, "pin name collision for #{constant}; label the nets uniquely" if declarations.key?(constant)
        declarations[constant] = number
      end
      raise ArgumentError, "no connected GPIO pins to export" if declarations.empty?
      lines = declarations.sort.map do |name, number|
        arduino ? "#define #{name} #{number}" : "#{name} = #{number}"
      end
      ([arduino ? "#pragma once" : "# MicroPython GPIO constants", "", *lines, ""]).join("\n")
    end

    def wokwi_pin(component, name)
      case component.part.id
      when "resistor" then name if %w[1 2].include?(name)
      when "led" then { "anode" => "A", "cathode" => "C" }[name]
      when "arduino_uno"
        return name.delete_prefix("D") if name.match?(/\AD(?:[0-9]|1[0-3])\z/)
        return name if name.match?(/\AA[0-5]\z/) || %w[5V VIN].include?(name)
        { "GND" => "GND.1", "GND2" => "GND.2", "GND3" => "GND.3" }[name]
      end
    end

    def spice_node(circuit, names, reference)
      net = circuit.net_of(reference)
      raise ArgumentError, "unconnected SPICE terminal #{reference}" unless net
      names.fetch(net.name)
    end

    def safe_identifier!(value, kind)
      raise ArgumentError, "invalid SPICE #{kind} reference #{value}" unless value.match?(/\A[A-Za-z][A-Za-z0-9_]*\z/)
    end

    def number(value)
      format("%.12g", value)
    end

    def xml(value)
      CGI.escapeHTML(value.to_s)
    end
  end
end
