# frozen_string_literal: true

module Breadkit
  class StructuredInput
    ROOT_KEYS = %w[title board boards use_parts use_boards supplies labels parts offboard wires connections expectations lint_disables].freeze

    def self.load_file(path)
      new(File.expand_path(path)).load_file
    end

    def self.load_source(path, source)
      new(File.expand_path(path), source: source).load_file
    end

    def initialize(path, source: nil)
      @path = path
      @source = source
      @location = SourceLocation.new(path: path, line: 1)
      @builder = DSL::Builder.new(base_dir: File.dirname(path))
    end

    def load_file
      source = @source || File.read(@path, encoding: "UTF-8")
      raw = @path.end_with?(".toml") ? parse_toml(source) : YAML.safe_load(source, aliases: false)
      data = mapping(raw, "root")
      allowed!(data, ROOT_KEYS, "root")
      @builder.document.source_root = File.dirname(@path)
      @builder.title(string(data["title"], "title")) if data.key?("title")
      raise DSLError, "board and boards cannot be used together" if data.key?("board") && data.key?("boards")
      load_board(data["board"]) if data.key?("board")
      if data.key?("boards")
        named = records(data, "boards")
        raise DSLError, "boards must contain at least one board" if named.empty?
        named.each_with_index { |item, index| load_named_board(item, "boards[#{index}]") }
      end
      paths(data, "use_parts").each { |item| @builder.use_parts(item) }
      paths(data, "use_boards").each { |item| @builder.use_boards(item) }
      records(data, "supplies").each_with_index { |item, index| load_supply(item, "supplies[#{index}]") }
      records(data, "labels").each_with_index { |item, index| load_label(item, "labels[#{index}]") }
      records(data, "parts").each_with_index { |item, index| load_part(item, "parts[#{index}]", offboard: false) }
      records(data, "offboard").each_with_index { |item, index| load_part(item, "offboard[#{index}]", offboard: true) }
      records(data, "wires").each_with_index { |item, index| load_wire(item, "wires[#{index}]") }
      records(data, "connections").each_with_index { |item, index| load_connection(item, "connections[#{index}]") }
      records(data, "expectations").each_with_index { |item, index| load_expectation(item, "expectations[#{index}]") }
      records(data, "lint_disables").each_with_index { |item, index| load_disable(item, "lint_disables[#{index}]") }
      document = @builder.document
      (document.supplies + document.labels + document.components + document.wires + document.lint_disables).each do |entry|
        entry[:location] = @location
      end
      document.expectations.each do |group|
        group[:location] = @location
        group[:entries].each { |entry| entry[:location] = @location }
      end
      document.diagnostics.map! do |item|
        Diagnostic.new(code: item.code, severity: item.severity, message: item.message,
                       location: @location, targets: item.targets)
      end
      document
    rescue Psych::Exception, DSLError, ArgumentError, TypeError => e
      raise DSLError.new("#{@path}: #{e.message}", location: @location)
    end

    private

    def parse_toml(source)
      require "tomlrb"
      Tomlrb.parse(source)
    rescue Tomlrb::ParseError => e
      raise DSLError, e.message
    end

    def load_board(value)
      if value.is_a?(String)
        @builder.board(string(value, "board"))
      else
        item = mapping(value, "board")
        allowed!(item, %w[type split_rails], "board")
        options = {}
        options[:split_rails] = boolean(item["split_rails"], "board.split_rails") if item.key?("split_rails")
        @builder.board(string(item["type"], "board.type"), **options)
      end
    end

    def load_named_board(value, context)
      item = mapping(value, context)
      allowed!(item, %w[name type split_rails], context)
      options = {}
      options[:split_rails] = boolean(item["split_rails"], "#{context}.split_rails") if item.key?("split_rails")
      @builder.board(string(item["type"], "#{context}.type"), as: string(item["name"], "#{context}.name"), **options)
    end

    def load_supply(value, context)
      item = mapping(value, context)
      if item.key?("from")
        allowed!(item, %w[from plus minus], context)
        @builder.supply(from: string(item["from"], "#{context}.from"),
                        plus: string(item["plus"], "#{context}.plus"),
                        minus: string(item["minus"], "#{context}.minus"))
        return
      end

      allowed!(item, %w[name voltage plus minus isolated current_limit], context)
      options = { voltage: number_or_range(item["voltage"], "#{context}.voltage"),
                  plus: string(item["plus"], "#{context}.plus"),
                  minus: string(item["minus"], "#{context}.minus") }
      options[:isolated] = boolean(item["isolated"], "#{context}.isolated") if item.key?("isolated")
      options[:current_limit] = item["current_limit"] if item.key?("current_limit")
      @builder.supply(string(item["name"], "#{context}.name"), **options)
    end

    def load_label(value, context)
      item = mapping(value, context)
      allowed!(item, %w[name at], context)
      @builder.net(string(item["name"], "#{context}.name"), at: string(item["at"], "#{context}.at"))
    end

    def load_part(value, context, offboard:)
      item = mapping(value, context)
      allowed!(item, %w[ref type value pins at attrs unused side offboard], context)
      is_offboard = offboard || item["offboard"] == true
      boolean(item["offboard"], "#{context}.offboard") if item.key?("offboard")
      attrs = item.key?("attrs") ? mapping(item["attrs"], "#{context}.attrs").transform_keys(&:to_sym) : {}
      ref = string(item["ref"], "#{context}.ref")
      type = string(item["type"], "#{context}.type")
      unused = item.key?("unused") ? strings(item["unused"], "#{context}.unused") : []
      if is_offboard
        raise DSLError, "#{context}.pins is unavailable for offboard parts" if item.key?("pins")
        raise DSLError, "#{context}.value is unavailable for offboard parts" if item.key?("value")
        side = item.key?("side") ? string(item["side"], "#{context}.side") : "left"
        at = item.key?("at") ? string(item["at"], "#{context}.at") : nil
        @builder.offboard(ref, type, side: side, at: at, unused: unused, **attrs)
      else
        raise DSLError, "#{context}.side requires offboard: true" if item.key?("side")
        pins = pins(item["pins"], "#{context}.pins") if item.key?("pins")
        at = item.key?("at") ? string(item["at"], "#{context}.at") : nil
        value = item["value"]
        unless value.nil? || value.is_a?(String) || value.is_a?(Numeric)
          raise DSLError, "#{context}.value must be text or a number"
        end
        @builder.part(ref, type, value, pins: pins, at: at, **attrs.merge(unused: unused))
      end
    end

    def load_wire(value, context)
      item = mapping(value, context)
      allowed!(item, %w[from to color id route layer electrical dashed], context)
      options = {}
      %w[color id route].each do |key|
        options[key.to_sym] = string(item[key], "#{context}.#{key}") if item.key?(key)
      end
      if item.key?("layer")
        layer = item["layer"]
        options[:layer] = layer.is_a?(Array) ? strings(layer, "#{context}.layer") : string(layer, "#{context}.layer")
      end
      %w[electrical dashed].each do |key|
        options[key.to_sym] = boolean(item[key], "#{context}.#{key}") if item.key?(key)
      end
      @builder.wire(string(item["from"], "#{context}.from"), string(item["to"], "#{context}.to"), **options)
    end

    def load_connection(value, context)
      item = mapping(value, context)
      allowed!(item, %w[from to when], context)
      options = {}
      options[:when] = string(item["when"], "#{context}.when") if item.key?("when")
      @builder.connect(string(item["from"], "#{context}.from"), string(item["to"], "#{context}.to"), **options)
    end

    def load_expectation(value, context)
      item = mapping(value, context)
      allowed!(item, %w[strict when connected isolated nets voltage current], context)
      strict = item.key?("strict") ? boolean(item["strict"], "#{context}.strict") : false
      group = { strict: strict, entries: [], location: @location }
      group[:when] = string(item["when"], "#{context}.when") if item.key?("when")
      %w[connected isolated].each do |kind|
        next unless item.key?(kind)
        groups(item[kind], "#{context}.#{kind}").each do |refs|
          group[:entries] << { kind: kind, refs: refs, location: @location }
        end
      end
      records(item, "nets", context).each_with_index do |record, index|
        entry = mapping(record, "#{context}.nets[#{index}]")
        allowed!(entry, %w[name refs], "#{context}.nets[#{index}]")
        group[:entries] << { kind: "net", name: string(entry["name"], "#{context}.nets[#{index}].name"),
                             refs: strings(entry["refs"], "#{context}.nets[#{index}].refs"), location: @location }
      end
      %w[voltage current].each do |kind|
        records(item, kind, context).each_with_index do |record, index|
          entry = mapping(record, "#{context}.#{kind}[#{index}]")
          allowed!(entry, %w[ref range], "#{context}.#{kind}[#{index}]")
          range = number_or_range(entry["range"], "#{context}.#{kind}[#{index}].range")
          raise DSLError, "#{context}.#{kind}[#{index}].range must be inclusive" unless range.is_a?(Range)
          limits = [Value.parse(range.begin), Value.parse(range.end)]
          unless limits.all?(&:finite?) && limits.first <= limits.last && (kind != "current" || !limits.first.negative?)
            raise DSLError, "#{context}.#{kind}[#{index}].range is invalid"
          end
          group[:entries] << { kind: kind, refs: [string(entry["ref"], "#{context}.#{kind}[#{index}].ref")],
                               range: limits, location: @location }
        end
      end
      @builder.document.expectations << group
    end

    def load_disable(value, context)
      item = mapping(value, context)
      allowed!(item, %w[rule on reason], context)
      options = {}
      options[:on] = string(item["on"], "#{context}.on") if item.key?("on")
      options[:reason] = string(item["reason"], "#{context}.reason") if item.key?("reason")
      @builder.lint_disable(string(item["rule"], "#{context}.rule"), **options)
    end

    def number_or_range(value, context)
      return value if value.is_a?(Numeric)
      raise DSLError, "#{context} must be a number or numeric string" unless value.is_a?(String)

      match = /\A(.+)\.\.(.+)\z/.match(value)
      match ? (Value.parse(match[1])..Value.parse(match[2])) : value
    end

    def mapping(value, context)
      unless value.is_a?(Hash) && value.keys.all? { |key| key.is_a?(String) }
        raise DSLError, "#{context} must be a mapping with text keys"
      end
      value
    end

    def allowed!(item, keys, context)
      unknown = item.keys - keys
      raise DSLError, "#{context} has unknown keys: #{unknown.join(', ')}" unless unknown.empty?
    end

    def records(item, key, context = "root")
      value = item.fetch(key, [])
      raise DSLError, "#{context}.#{key} must be a list" unless value.is_a?(Array)
      value
    end

    def paths(item, key)
      value = item.fetch(key, [])
      value = [value] if value.is_a?(String)
      strings(value, key)
    end

    def strings(value, context)
      raise DSLError, "#{context} must be a list of text" unless value.is_a?(Array)
      value.map.with_index { |item, index| string(item, "#{context}[#{index}]") }
    end

    def groups(value, context)
      raise DSLError, "#{context} must be a list of reference lists" unless value.is_a?(Array)
      value.map.with_index do |item, index|
        refs = strings(item, "#{context}[#{index}]")
        raise DSLError, "#{context}[#{index}] needs at least two references" if refs.length < 2
        refs
      end
    end

    def pins(value, context)
      return strings(value, context) if value.is_a?(Array)
      item = mapping(value, context)
      item.transform_values { |hole| string(hole, "#{context} pin") }
    end

    def string(value, context)
      raise DSLError, "#{context} must be nonempty text" unless value.is_a?(String) && !value.empty?
      value
    end

    def boolean(value, context)
      raise DSLError, "#{context} must be boolean" unless [true, false].include?(value)
      value
    end
  end
end
