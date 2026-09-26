# frozen_string_literal: true

module Breadkit
  class PartDef
    attr_reader :data

    def initialize(data)
      @data = data
      raise ArgumentError, "part definition needs an id" unless data["id"]
      raise ArgumentError, "part #{data['id']} needs pins" unless data["pins"].is_a?(Array)
      identities = {}
      pins.each_with_index do |pin, index|
        raise ArgumentError, "part #{id} has invalid pin" unless pin.is_a?(Hash) && pin["num"]

        ([pin["num"], pin["name"]] + Array(pin["aliases"])).compact.each do |identity|
          key = identity.to_s.downcase
          raise ArgumentError, "part #{id} has duplicate pin identity #{identity}" if identities.key?(key) && identities[key] != index

          identities[key] = index
        end
      end
      valid_pins = pins.flat_map { |pin| [pin["num"], pin["name"], *Array(pin["aliases"])].compact.map(&:to_s) }
      %w[internal switch same_strip_ok].each do |key|
        Array(data[key]).each do |pair|
          raise ArgumentError, "part #{id} has invalid #{key} pin pair #{pair.inspect}" unless pair.length == 2 && pair.all? { |pin| valid_pins.include?(pin.to_s) }
        end
      end
      raise ArgumentError, "part #{id} has invalid placement" unless %w[leads dip footprint offboard].include?(placement)
      if data["polarity"]
        unless data["polarity"].is_a?(Hash) && data["polarity"].values.all? { |name| identities.key?(name.to_s.downcase) }
          raise ArgumentError, "part #{id} has invalid polarity pin reference"
        end
      end
      if data["footprint"]
        numbers = pins.map { |pin| pin.fetch("num").to_s }
        unless data["footprint"].is_a?(Hash) && data["footprint"].all? { |key, offset| numbers.include?(key.to_s) && offset.is_a?(Array) && offset.length == 2 && offset.all? { |value| value.is_a?(Integer) } }
          raise ArgumentError, "part #{id} has invalid footprint pin reference or offset"
        end
      end
      if data.dig("render", "shape") == "module"
        size_mm = data.dig("render", "size_mm")
        raise ArgumentError, "part #{id} module rendering needs positive size_mm [width, height]" unless valid_mm_pair?(size_mm, positive: true)
        offset_mm = data.dig("render", "body_offset_mm")
        if offset_mm && !valid_mm_pair?(offset_mm, positive: false)
          raise ArgumentError, "part #{id} module rendering needs finite body_offset_mm [x, y]"
        end
      end
    end

    def id
      data.fetch("id")
    end

    def pins
      data.fetch("pins")
    end

    def placement
      data.fetch("placement", "leads")
    end

    def pin(value)
      key = value.to_s.downcase
      pins.find do |pin|
        ([pin["num"], pin["name"]] + Array(pin["aliases"])).compact.any? { |item| item.to_s.downcase == key }
      end
    end

    private

    def valid_mm_pair?(values, positive:)
      values.is_a?(Array) && values.length == 2 && values.all? do |value|
        number = Float(value)
        number.finite? && (!positive || number.positive?)
      rescue ArgumentError, TypeError
        false
      end
    end
  end

  class PartLibrary
    def initialize(extra_paths: [], extra_definitions: [])
      paths = Dir.glob(File.expand_path("../../data/parts/*.yml", __dir__))
      paths.concat(extra_paths.flat_map { |path| Dir.glob(path) })
      definitions = paths.uniq.map { |path| YAML.safe_load(File.read(path, encoding: "UTF-8"), aliases: false) }
      definitions.concat(extra_definitions)
      @parts = {}
      definitions.each do |data|
        part = PartDef.new(data)
        ([part.id] + Array(data["aliases"])).each do |name|
          key = name.to_s.downcase
          raise ArgumentError, "part alias #{name} conflicts with #{@parts[key].id}" if @parts[key] && @parts[key] != part

          @parts[key] = part
        end
      end
    end

    def find(name, pin_count: nil)
      key = name.to_s.downcase
      return @parts[key] if @parts[key]
      return unless %w[dip pin_header].include?(key) && pin_count

      count = Integer(pin_count)
      return unless count.between?(key == "dip" ? 2 : 1, 64) && (key != "dip" || count.even?)
      generic(key, count)
    rescue ArgumentError, TypeError
      nil
    end

    def all
      (@parts.values.uniq + %w[dip pin_header].map { |id| generic(id, 2) }).sort_by(&:id)
    end

    private

    def generic(id, count)
      pins = (1..count).map { |number| { "num" => number, "name" => number.to_s } }
      data = { "id" => id, "placement" => id == "dip" ? "dip" : "footprint", "pins" => pins,
               "package" => { "pins" => count }, "render" => { "shape" => id == "dip" ? "dip" : "generic" } }
      data["footprint"] = (1..count).to_h { |number| [number.to_s, [number - 1, 0]] } if id == "pin_header"
      PartDef.new(data)
    end
  end
end
