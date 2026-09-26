# frozen_string_literal: true

require "pathname"

module Breadkit
  module IR
    class Writer
      def write(circuit)
        library = PartLibrary.new
        part_definitions = circuit.components.values.map(&:part).uniq.filter_map do |part|
          standard = library.find(part.id, pin_count: part.pins.length)
          part.data unless standard&.data == part.data
        end
        result = {
          schema_version: 1,
          title: circuit.title,
          board: { type: circuit.board.definition.id, options: { split_rails: circuit.board.split_rails } },
          board_definition: circuit.board.definition.data,
          supplies: circuit.supplies.map { |item| { name: item.name, voltage: item.voltage, plus: item.plus, minus: item.minus, source: source(item.location) } },
          labels: circuit.labels.map { |item| { net: item.name, at: item.at, source: source(item.location) } },
          components: circuit.components.values.map do |component|
            { ref: component.ref, part: component.part.id, value: component.value,
              attrs: stringify(component.attrs), pins: component.pins.transform_values(&:hole_id),
              unused: component.unused, source: source(component.location) }
          end,
          wires: circuit.wires.map { |wire| { id: wire.id, from: wire.from, to: wire.to, color: wire.color, route: wire.route,
                                               layer: wire.layer, electrical: wire.electrical, dashed: wire.dashed,
                                               source: source(wire.location) } },
          expectations: stringify(circuit.expectations),
          lint_disables: stringify(circuit.lint_disables),
          analysis: { nets: circuit.nets.map { |net| { name: net.name, members: net.members, holes: net.holes, potential: circuit.potentials.values[net.name] } } }
        }
        result[:part_definitions] = part_definitions unless part_definitions.empty?
        result
      end

      private

      def source(location)
        return nil unless location && location.path && location.line

        path = Pathname.new(location.path)
        path = path.relative_path_from(Pathname.pwd) if path.absolute?
        { path: path.to_s, line: location.line }
      end

      def stringify(value)
        case value
        when Hash then value.each_with_object({}) { |(key, item), result| result[key.to_s] = stringify(item) }
        when Array then value.map { |item| stringify(item) }
        when SourceLocation then source(value).transform_keys(&:to_s)
        when Struct then value.each_pair.each_with_object({}) { |(key, item), result| result[key.to_s] = stringify(item) }
        when Symbol then value.to_s
        else value
        end
      end
    end

    class Reader
      def read_file(path)
        read(JSON.parse(File.read(path, encoding: "UTF-8")))
      rescue JSON::ParserError => e
        raise DSLError, "#{path}: invalid IR JSON: #{e.message}"
      end

      def read(data)
        data = stringify_keys(data)
        validate!(data)
        doc = Document.new
        doc.title = data["title"]
        doc.board = { type: data.dig("board", "type") || "full", options: (data.dig("board", "options") || {}).transform_keys(&:to_sym) }
        doc.board_definitions = [data["board_definition"]] if data["board_definition"]
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
        doc.part_definitions = Array(data["part_definitions"])
        doc.wires = Array(data["wires"]).map do |item|
          { id: item["id"], from: item.fetch("from"), to: item.fetch("to"), color: item["color"],
            route: item["route"] || "straight", layer: item["layer"], electrical: item["electrical"] != false,
            dashed: item["dashed"] == true, location: location(item["source"]) }
        end
        doc.expectations = Array(data["expectations"])
        doc.lint_disables = Array(data["lint_disables"]).map do |item|
          { rule: item.fetch("rule"), on: item["on"], reason: item["reason"], location: location(item["location"]) }
        end
        Resolver.new.call(doc)
      rescue KeyError => e
        raise DSLError, "invalid IR: missing #{e.key}"
      end

      private

      def validate!(data)
        require_hash(data, "root")
        raise DSLError, "unsupported IR schema_version" unless data["schema_version"] == 1
        raise DSLError, "invalid IR: title must be text or null" unless data["title"].nil? || data["title"].is_a?(String)

        board = require_hash(data["board"], "board")
        require_string(board["type"], "board.type")
        options = require_hash(board["options"], "board.options")
        unless !options.key?("split_rails") || [true, false].include?(options["split_rails"])
          raise DSLError, "invalid IR: board.options.split_rails must be boolean"
        end
        validate_board_definition(data["board_definition"]) if data.key?("board_definition")
        validate_records(data, "supplies", %w[name plus minus], %w[voltage])
        validate_records(data, "labels", %w[net at])
        validate_records(data, "components", %w[ref part])
        validate_records(data, "wires", %w[id from to])
        validate_records(data, "expectations")
        validate_records(data, "part_definitions") if data.key?("part_definitions")
        validate_records(data, "lint_disables", %w[rule]) if data.key?("lint_disables")
        Array(data["part_definitions"]).each_with_index do |item, index|
          require_string(item["id"], "part_definitions[#{index}].id")
          require_array(item["pins"], "part_definitions[#{index}].pins").each do |pin|
            require_hash(pin, "part_definitions[#{index}].pins item")
          end
        end
        Array(data["lint_disables"]).each_with_index do |item, index|
          require_source(item["location"], "lint_disables[#{index}].location") if item.key?("location")
        end
        data.fetch("components").each_with_index do |item, index|
          require_hash(item["pins"], "components[#{index}].pins").each_value do |hole|
            raise DSLError, "invalid IR: components[#{index}].pins values must be text or null" unless hole.nil? || hole.is_a?(String)
          end
          require_hash(item["attrs"], "components[#{index}].attrs")
          require_array(item["unused"], "components[#{index}].unused")
        end
        data.fetch("expectations").each_with_index do |item, index|
          require_source(item["location"], "expectations[#{index}].location")
          require_array(item["entries"], "expectations[#{index}].entries")
          item["entries"].each_with_index do |entry, entry_index|
            require_hash(entry, "expectations[#{index}].entries[#{entry_index}]")
            unless %w[connected isolated net].include?(entry["kind"])
              raise DSLError, "invalid IR: expectations[#{index}].entries[#{entry_index}].kind is unknown"
            end
            require_array(entry["refs"], "expectations[#{index}].entries[#{entry_index}].refs")
            require_source(entry["location"], "expectations[#{index}].entries[#{entry_index}].location")
          end
        end
        require_array(require_hash(data["analysis"], "analysis")["nets"], "analysis.nets") if data.key?("analysis")
      end

      def validate_board_definition(value)
        board = require_hash(value, "board_definition")
        require_string(board["id"], "board_definition.id")
        terminal = require_hash(board["terminal"], "board_definition.terminal")
        unless terminal["columns"].is_a?(Integer) && terminal["columns"].positive?
          raise DSLError, "invalid IR: board_definition.terminal.columns must be a positive integer"
        end
        require_array(terminal["rows"], "board_definition.terminal.rows").each do |row|
          require_string(row, "board_definition.terminal.rows item")
        end
        require_array(terminal["groups"], "board_definition.terminal.groups").each do |group|
          require_array(group, "board_definition.terminal.groups item")
        end
      end

      def validate_records(data, key, strings = [], numbers = [])
        require_array(data[key], key).each_with_index do |item, index|
          require_hash(item, "#{key}[#{index}]")
          strings.each { |field| require_string(item[field], "#{key}[#{index}].#{field}") }
          numbers.each do |field|
            raise DSLError, "invalid IR: #{key}[#{index}].#{field} must be a number" unless item[field].is_a?(Numeric)
          end
          require_source(item["source"], "#{key}[#{index}].source") if item.key?("source")
        end
      end

      def require_source(value, path)
        return if value.nil?

        require_hash(value, path)
        require_string(value["path"], "#{path}.path")
        raise DSLError, "invalid IR: #{path}.line must be a positive integer" unless value["line"].is_a?(Integer) && value["line"].positive?
      end

      def require_hash(value, path)
        raise DSLError, "invalid IR: #{path} must be an object" unless value.is_a?(Hash)

        value
      end

      def require_array(value, path)
        raise DSLError, "invalid IR: #{path} must be an array" unless value.is_a?(Array)

        value
      end

      def require_string(value, path)
        raise DSLError, "invalid IR: #{path} must be text" unless value.is_a?(String)
      end

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
