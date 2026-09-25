# frozen_string_literal: true

module Breadkit
  class PartDef
    attr_reader :data

    def initialize(data)
      @data = data
      raise ArgumentError, "part definition needs an id" unless data["id"]
      raise ArgumentError, "part #{data['id']} needs pins" unless data["pins"].is_a?(Array)
      valid_pins = pins.flat_map { |pin| [pin["num"], pin["name"], *Array(pin["aliases"])].compact.map(&:to_s) }
      %w[internal switch same_strip_ok].each do |key|
        Array(data[key]).each do |pair|
          raise ArgumentError, "part #{id} has invalid #{key} pin pair #{pair.inspect}" unless pair.length == 2 && pair.all? { |pin| valid_pins.include?(pin.to_s) }
        end
      end
      raise ArgumentError, "part #{id} has invalid placement" unless %w[leads dip footprint offboard].include?(placement)
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
  end

  class PartLibrary
    def initialize(extra_paths: [])
      paths = Dir.glob(File.expand_path("../../data/parts/*.yml", __dir__))
      paths.concat(extra_paths.flat_map { |path| Dir.glob(path) })
      @parts = {}
      paths.uniq.each do |path|
        data = YAML.safe_load(File.read(path), aliases: false)
        part = PartDef.new(data)
        ([part.id] + Array(data["aliases"])).each { |name| @parts[name.to_s.downcase] = part }
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
      data = { "id" => id, "placement" => id == "dip" ? "dip" : "leads", "pins" => pins,
               "package" => { "pins" => count }, "render" => { "shape" => id == "dip" ? "dip" : "generic" } }
      PartDef.new(data)
    end
  end
end
