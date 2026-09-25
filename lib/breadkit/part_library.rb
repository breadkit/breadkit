# frozen_string_literal: true

module Breadkit
  class PartDef
    attr_reader :data

    def initialize(data)
      @data = data
      raise ArgumentError, "part definition needs an id" unless data["id"]
      raise ArgumentError, "part #{data['id']} needs pins" unless data["pins"].is_a?(Array)
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

    def find(name)
      @parts[name.to_s.downcase]
    end

    def all
      @parts.values.uniq.sort_by(&:id)
    end
  end
end
