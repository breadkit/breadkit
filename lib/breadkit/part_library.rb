# frozen_string_literal: true

require "uri"

module Breadkit
  class PartDef
    attr_reader :data

    KEYS = %w[id aliases category placement pins polarity footprint footprint_mm internal switch independent_switches same_strip_ok straddle package render flags supply_range transistor_polarity attributes required_attributes provides extends override max_reverse_voltage forward_voltage on_resistance max_forward_current max_lead_span_mm datasheet_url].freeze
    PIN_KEYS = %w[num name aliases type role label max_voltage max_current output_capable mount].freeze

    def initialize(data)
      if data["pins"].is_a?(Array)
        data = data.merge("pins" => data["pins"].map do |pin|
          next pin unless pin.is_a?(Hash) && pin.key?("role")
          raise ArgumentError, "part #{data['id']} pin #{pin['num']} has both type and role" if pin.key?("type")
          pin.merge("type" => pin["role"]).reject { |key, _value| key == "role" }
        end)
      end
      @data = data
      unknown = data.keys - KEYS
      raise ArgumentError, "part #{data['id']} has unknown keys: #{unknown.join(', ')}" unless unknown.empty?
      raise ArgumentError, "part definition needs an id" unless data["id"]
      raise ArgumentError, "part #{data['id']} needs pins" unless data["pins"].is_a?(Array)
      if data.key?("datasheet_url")
        valid_url = begin
          url = data["datasheet_url"]
          parsed = URI.parse(url) if url.is_a?(String)
          parsed.is_a?(URI::HTTPS) && !parsed.host.to_s.empty? && !parsed.userinfo
        rescue URI::InvalidURIError
          false
        end
        raise ArgumentError, "part #{id} has invalid datasheet_url" unless valid_url
      end
      if data.key?("attributes")
        attributes = data["attributes"]
        unless attributes.is_a?(Hash) && attributes.all? { |key, schema| key.is_a?(String) &&
                 (schema == "css_color" || (schema.is_a?(Array) && !schema.empty? && schema.all? { |value| value.is_a?(String) || value.is_a?(Numeric) })) }
          raise ArgumentError, "part #{id} has invalid attributes schema"
        end
      end
      if data.key?("required_attributes")
        required = data["required_attributes"]
        unless required.is_a?(Array) && required.uniq.length == required.length &&
               required.all? { |key| key.is_a?(String) && data.fetch("attributes", {}).key?(key) }
          raise ArgumentError, "part #{id} has invalid required_attributes"
        end
      end
      identities = {}
      pins.each_with_index do |pin, index|
        raise ArgumentError, "part #{id} has invalid pin" unless pin.is_a?(Hash) && pin["num"]
        unknown_pin_keys = pin.keys - PIN_KEYS
        raise ArgumentError, "part #{id} has unknown pin keys: #{unknown_pin_keys.join(', ')}" unless unknown_pin_keys.empty?
        role = pin["type"]
        if role && !%w[input output gpio power ground data clock interrupt address nc passive analog reset open_drain].include?(role.to_s)
          raise ArgumentError, "part #{id} pin #{pin['num']} has invalid type #{role}"
        end
        raise ArgumentError, "part #{id} pin #{pin['num']} has invalid mount" if pin.key?("mount") && pin["mount"] != "rail"
        unless !pin.key?("label") || pin["label"].is_a?(String) || [true, false].include?(pin["label"])
          raise ArgumentError, "part #{id} pin #{pin['num']} has invalid label"
        end
        if pin.key?("max_voltage")
          voltage = pin["max_voltage"]
          raise ArgumentError, "part #{id} pin #{pin['num']} has invalid max_voltage" unless voltage.is_a?(Numeric) && voltage.finite? && voltage.positive?
        end
        if pin.key?("max_current")
          current = pin["max_current"]
          unless current.is_a?(Numeric) && current.real? && current.finite? && current.positive?
            raise ArgumentError, "part #{id} pin #{pin['num']} has invalid max_current"
          end
        end
        if pin.key?("output_capable") && ![true, false].include?(pin["output_capable"])
          raise ArgumentError, "part #{id} pin #{pin['num']} has invalid output_capable"
        end

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
      if data.key?("independent_switches")
        pairs = Array(data["switch"])
        terminals = pairs.flatten.map { |reference| pin(reference).fetch("num").to_s }
        unless data["independent_switches"] == true && !pairs.empty? && terminals.uniq.length == terminals.length
          raise ArgumentError, "part #{id} has invalid independent_switches; contacts must use distinct pins"
        end
      end
      raise ArgumentError, "part #{id} has invalid placement" unless %w[leads dip footprint offboard].include?(placement)
      if data.key?("max_lead_span_mm")
        limit = data["max_lead_span_mm"]
        unless placement == "leads" && pins.length == 2 && limit.is_a?(Numeric) && limit.real? && limit.finite? && limit.positive?
          raise ArgumentError, "part #{id} has invalid max_lead_span_mm"
        end
      end
      if data["render"]
        render = data["render"]
        unknown_render = render.is_a?(Hash) ? render.keys - %w[shape label size_mm body_offset_mm fill stroke text_color svg] : []
        unless render.is_a?(Hash) && unknown_render.empty? && (!render.key?("shape") || render["shape"].is_a?(String)) &&
               (!render.key?("label") || render["label"].is_a?(String)) &&
               (!render.key?("svg") || render["svg"].is_a?(String)) &&
               %w[fill stroke text_color].all? { |key| !render.key?(key) || Color.valid?(render[key]) }
          raise ArgumentError, "part #{id} has invalid render options#{": #{unknown_render.join(', ')}" unless unknown_render.empty?}"
        end
        if render.key?("size_mm") && !valid_mm_pair?(render["size_mm"], positive: true)
          raise ArgumentError, "part #{id} module rendering needs positive size_mm [width, height]"
        end
        if render.key?("body_offset_mm") && !valid_mm_pair?(render["body_offset_mm"], positive: false)
          raise ArgumentError, "part #{id} module rendering needs finite body_offset_mm [x, y]"
        end
      end
      if data["polarity"]
        unless data["polarity"].is_a?(Hash) && (data["polarity"].keys - %w[positive negative]).empty? &&
               data["polarity"].values.all? { |name| identities.key?(name.to_s.downcase) }
          raise ArgumentError, "part #{id} has invalid polarity pin reference"
        end
      end
      if data.key?("max_reverse_voltage")
        limit = data["max_reverse_voltage"]
        raise ArgumentError, "part #{id} has invalid max_reverse_voltage" unless limit.is_a?(Numeric) && limit.finite? && limit >= 0
      end
      %w[forward_voltage on_resistance max_forward_current].each do |key|
        next unless data.key?(key)

        value = data[key]
        raise ArgumentError, "part #{id} has invalid #{key}" unless value.is_a?(Numeric) && value.finite? && value.positive?
      end
      Array(data["provides"]).each do |source|
        unless source.is_a?(Hash) && %w[positive negative voltage].all? { |key| source.key?(key) } &&
               (source.keys - %w[positive negative voltage voltage_range when]).empty? &&
               %w[positive negative].all? { |key| identities.key?(source[key].to_s.downcase) } &&
               source["voltage"].is_a?(Numeric) && source["voltage"].finite? && source["voltage"].positive?
          raise ArgumentError, "part #{id} has invalid voltage source"
        end
        if source.key?("voltage_range")
          range = source["voltage_range"]
          unless range.is_a?(Array) && range.length == 2 &&
                 range.all? { |value| value.is_a?(Numeric) && value.finite? && value.positive? } &&
                 range[0] <= source["voltage"] && source["voltage"] <= range[1]
            raise ArgumentError, "part #{id} has invalid voltage source range"
          end
        end
        conditions = source["when"]
        if conditions && (!conditions.is_a?(Hash) || conditions.empty? || conditions.any? do |key, value|
          choices = data.fetch("attributes", {})[key]
          !choices.is_a?(Array) || !choices.include?(value)
        end)
          raise ArgumentError, "part #{id} has invalid voltage source condition"
        end
      end
      if data["footprint"]
        numbers = pins.map { |pin| pin.fetch("num").to_s }
        unless data["footprint"].is_a?(Hash) && data["footprint"].all? { |key, offset| numbers.include?(key.to_s) && offset.is_a?(Array) && offset.length == 2 && offset.all? { |value| value.is_a?(Integer) } }
          raise ArgumentError, "part #{id} has invalid footprint pin reference or offset"
        end
      end
      if data.key?("footprint_mm")
        offsets = data["footprint_mm"]
        numbers = pins.map { |pin| pin.fetch("num").to_s }
        raise ArgumentError, "part #{id} cannot set both footprint_mm and footprint" if data.key?("footprint")
        unless placement == "footprint" && offsets.is_a?(Hash) && offsets.keys.sort == numbers.sort &&
               offsets.values.all? { |pair| pair.is_a?(Array) && pair.length == 2 && pair.all? { |value| grid_offset_mm?(value) } }
          raise ArgumentError, "part #{id} has invalid footprint_mm; pin offsets must align to 2.54 mm holes"
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

    def max_lead_span_mm
      data["max_lead_span_mm"]&.to_f
    end

    def footprint
      return data["footprint"] if data.key?("footprint")

      data["footprint_mm"]&.transform_values { |pair| pair.map { |value| (value / 2.54).round } }
    end

    def pin(value)
      key = value.to_s.downcase
      pins.find do |pin|
        ([pin["num"], pin["name"]] + Array(pin["aliases"])).compact.any? { |item| item.to_s.downcase == key }
      end
    end

    private

    def grid_offset_mm?(value)
      value.is_a?(Numeric) && value.real? && value.finite? &&
        ((value / 2.54) - (value / 2.54).round).abs < 1e-6
    end

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
    attr_reader :warnings

    def initialize(extra_paths: [], extra_definitions: [])
      builtin_paths = Dir.glob(File.expand_path("../../data/parts/*.yml", __dir__))
      paths = builtin_paths + extra_paths.flat_map { |path| Dir.glob(path) }
      definitions = paths.uniq.map { |path| YAML.safe_load(File.read(path, encoding: "UTF-8"), aliases: false) }
      definitions.concat(extra_definitions)
      @parts = {}
      @warnings = []
      definitions.each do |data|
        if data["extends"]
          parent = @parts[data["extends"].to_s.downcase]
          raise ArgumentError, "unknown parent part #{data['extends']}" unless parent
          data = parent.data.merge("aliases" => []).merge(data)
        end
        existing = @parts[data["id"].to_s.downcase]
        if existing && (data["override"] || data["extends"])
          @parts.delete_if { |_key, item| item == existing }
          @warnings << "part #{data['id']} overrides #{existing.id}"
        end
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
