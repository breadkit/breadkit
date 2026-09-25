# frozen_string_literal: true

module Breadkit
  module IR
    class Writer
      def write(circuit)
        result = {
          schema_version: 1,
          title: circuit.title,
          board: { type: circuit.board.definition.id, options: { split_rails: circuit.board.split_rails } },
          supplies: circuit.supplies.map { |item| { name: item.name, voltage: item.voltage, plus: item.plus, minus: item.minus, source: source(item.location) } },
          labels: circuit.labels.map { |item| { net: item.name, at: item.at, source: source(item.location) } },
          components: circuit.components.values.map do |component|
            { ref: component.ref, part: component.part.id, value: component.value,
              attrs: stringify(component.attrs), pins: component.pins.transform_values(&:hole_id),
              unused: component.unused, source: source(component.location) }
          end,
          wires: circuit.wires.map { |wire| { id: wire.id, from: wire.from, to: wire.to, color: wire.color, route: wire.route, source: source(wire.location) } },
          expectations: stringify(circuit.expectations),
          analysis: { nets: circuit.nets.map { |net| { name: net.name, members: net.members, holes: net.holes, potential: circuit.potentials.values[net.name] } } }
        }
        result
      end

      private

      def source(location)
        return nil unless location
        { path: location.path, line: location.line }
      end

      def stringify(value)
        case value
        when Hash then value.each_with_object({}) { |(key, item), result| result[key.to_s] = stringify(item) }
        when Array then value.map { |item| stringify(item) }
        when Struct then value.each_pair.each_with_object({}) { |(key, item), result| result[key.to_s] = stringify(item) }
        when Symbol then value.to_s
        else value
        end
      end
    end

    class Reader
      def read_file(path)
        read(JSON.parse(File.read(path)))
      rescue JSON::ParserError => e
        raise DSLError, "#{path}: invalid IR JSON: #{e.message}"
      end

      def read(data)
        data = stringify_keys(data)
        raise DSLError, "unsupported IR schema_version" unless data["schema_version"] == 1
        doc = Document.new
        doc.title = data["title"]
        doc.board = { type: data.dig("board", "type") || "full", options: (data.dig("board", "options") || {}).transform_keys(&:to_sym) }
        doc.supplies = Array(data["supplies"]).map do |item|
          { name: item.fetch("name"), voltage: Value.parse(item.fetch("voltage")), plus: item.fetch("plus"), minus: item.fetch("minus"), location: location(item["source"]) }
        end
        doc.labels = Array(data["labels"]).map do |item|
          { name: item.fetch("net"), at: item.fetch("at"), location: location(item["source"]) }
        end
        doc.components = Array(data["components"]).map do |item|
          { ref: item.fetch("ref"), type: item.fetch("part"), value: item["value"],
            pins: item["pins"] || {}, at: nil, attrs: (item["attrs"] || {}).transform_keys(&:to_sym),
            unused: item["unused"] || [], location: location(item["source"]) }
        end
        doc.wires = Array(data["wires"]).map do |item|
          { id: item["id"], from: item.fetch("from"), to: item.fetch("to"), color: item["color"], route: item["route"] || "straight", location: location(item["source"]) }
        end
        doc.expectations = Array(data["expectations"])
        Resolver.new.call(doc)
      rescue KeyError => e
        raise DSLError, "invalid IR: missing #{e.key}"
      end

      private

      def location(source)
        return nil unless source
        SourceLocation.new(path: source["path"], line: source["line"])
      end

      def stringify_keys(value)
        case value
        when Hash then value.each_with_object({}) { |(key, item), result| result[key.to_s] = stringify_keys(item) }
        when Array then value.map { |item| stringify_keys(item) }
        else value
        end
      end
    end
  end
end
