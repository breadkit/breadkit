# frozen_string_literal: true

require "timeout"

module Breadkit
  module DSL
    METHODS = %w[title board use_parts use_boards include block use_block bus step supply net part wire connect offboard expect expect_voltage expect_current lint_disable resistor capacitor electrolytic diode led transistor pot button ic connected isolated].freeze

    class Builder
      attr_reader :document

      def initialize(base_dir: Dir.pwd)
        @document = Document.new
        @expected = nil
        @base_dir = base_dir
        @include_stack = []
        @blocks = {}
        @active_blocks = []
        @current_step = nil
      end

      def title(value)
        document.title = value.to_s
      end

      def board(type, as: nil, **options)
        unknown = options.keys - [:split_rails]
        raise DSLError, "unknown board option #{unknown.first}" unless unknown.empty?
        if options.key?(:split_rails) && ![true, false].include?(options[:split_rails])
          raise DSLError, "split_rails must be boolean"
        end

        if as
          raise DSLError, "named and unnamed boards cannot be mixed" if @board_declared
          name = helper_name(as, "board")
          if document.boards.any? { |item| item[:name].casecmp?(name) }
            raise DSLError, "duplicate board name #{name}"
          end
          document.boards << { name: name, type: type.to_s, options: options }
        else
          raise DSLError, "named and unnamed boards cannot be mixed" unless document.boards.empty?
          raise DSLError, "board may only be declared once" if @board_declared

          @board_declared = true
          document.board = { type: type.to_s, options: options }
        end
      end

      def use_parts(path)
        matches = Dir.glob(resolve_path(path))
        document.diagnostics << Diagnostic.new(code: "unmatched_parts", severity: "warning",
                                               message: "no part definitions match #{path}", location: source_location,
                                               targets: []) if matches.empty?
        document.part_paths.concat(matches)
      end

      def use_boards(path)
        document.board_paths.concat(Dir.glob(resolve_path(path)))
      end

      def include(path)
        absolute = resolve_path(path)
        raise DSLError.new("circular include: #{absolute}", location: source_location) if @include_stack.include?(absolute)

        previous_dir = @base_dir
        @include_stack << absolute
        @base_dir = File.dirname(absolute)
        instance_eval(File.read(absolute, encoding: "UTF-8"), absolute, 1)
      rescue DSLError, ScriptError => e
        frame = e.backtrace_locations&.find { |item| item.path == absolute }
        location = e.respond_to?(:location) && e.location || SourceLocation.new(path: absolute, line: frame&.lineno)
        raise DSLError.new(e.message, location: location)
      ensure
        if previous_dir
          @base_dir = previous_dir
          @include_stack.pop
        end
      end

      def block(name, &body)
        key = helper_name(name, "block")
        raise DSLError, "block #{key} requires a body" unless body
        raise DSLError, "block #{key} is already defined" if @blocks.key?(key)

        @blocks[key] = body
      end

      def use_block(name, *args, **kwargs)
        active = false
        key = helper_name(name, "block")
        body = @blocks[key]
        raise DSLError, "unknown block #{key}" unless body
        raise DSLError, "recursive block #{key}" if @active_blocks.include?(key)

        @active_blocks << key
        active = true
        instance_exec(*args, **kwargs, &body)
      ensure
        @active_blocks.pop if active
      end

      def bus(name, **lines)
        prefix = helper_name(name, "bus").upcase
        raise DSLError, "bus #{prefix} must declare at least one line" if lines.empty?
        raise DSLError, "bus cannot be declared inside expect" if @expected

        labels = {}
        lines.each do |line, reference|
          key = helper_name(line, "bus line").upcase
          raise DSLError, "duplicate bus line #{key}" if labels.key?(key)
          raise DSLError, "bus line #{key} reference must be text" unless reference.is_a?(String) && !reference.empty?

          labels[key] = reference
        end
        labels.each { |line, reference| net "#{prefix}_#{line}", at: reference }
      end

      def step(number, title: nil, &body)
        active = false
        raise DSLError, "nested step declarations are not allowed" if @current_step
        expected = document.steps.length + 1
        raise DSLError, "step number must be #{expected}" unless number.is_a?(Integer) && number == expected
        raise DSLError, "step title must be nonempty text" unless title.nil? || (title.is_a?(String) && !title.empty?)
        raise DSLError, "step #{number} requires a body" unless body

        document.steps << { number: number, title: title, source: source_location }
        @current_step = number
        active = true
        instance_eval(&body)
      ensure
        @current_step = nil if active
      end

      def supply(name = nil, voltage: nil, plus: nil, minus: nil, from: nil, isolated: false, current_limit: nil)
        if from
          raise DSLError, "supply from: cannot mix standalone supply options" if name || voltage || isolated != false || current_limit
          raise DSLError, "supply from: requires plus and minus destinations" unless plus && minus
          unless [from, plus, minus].all? { |value| value.is_a?(String) && !value.empty? }
            raise DSLError, "supply from:, plus:, and minus: must be nonempty text"
          end

          document.wires << { supply_from: from, plus: plus, minus: minus,
                              location: source_location, step: @current_step }
          return
        end

        raise DSLError, "supply requires name, voltage, plus, and minus" unless name && voltage && plus && minus

        range = voltage.is_a?(Range) ? [Value.parse(voltage.begin), Value.parse(voltage.end)] : nil
        raise DSLError, "supply voltage range must be inclusive and ascending" if range && (voltage.exclude_end? || range[0] > range[1])
        parsed = range ? (range[0] + range[1]) / 2.0 : Value.parse(voltage)
        raise DSLError, "supply voltage must be positive" unless parsed.finite? && parsed.positive?
        raise DSLError, "supply voltage range must be positive" if range && range.any? { |value| !value.finite? || !value.positive? }
        raise DSLError, "isolated must be boolean" unless [true, false].include?(isolated)
        if !current_limit.nil? && (!current_limit.is_a?(Numeric) || !current_limit.real? || !current_limit.finite? || !current_limit.positive?)
          raise DSLError, "current_limit must be a positive current in amperes"
        end
        document.supplies << { name: name.to_s, voltage: parsed, plus: plus.to_s,
                               minus: minus.to_s, isolated: isolated, voltage_range: range,
                               current_limit: current_limit, location: source_location, step: @current_step }
      end

      def net(name, *refs, at: nil, **options)
        if @expected
          @expected << { kind: "net", name: name.to_s, refs: (refs + [at] + options.values).compact.map(&:to_s), location: source_location }
        else
          raise DSLError, "net requires at: outside expect" if at.nil? || !refs.empty? || !options.empty?

          document.labels << { name: name.to_s, at: at.to_s, location: source_location, step: @current_step }
        end
      end

      def part(ref, type, value = nil, pins: nil, at: nil, **attrs)
        unsupported = attrs.keys.find { |key| key.to_sym == :wire_layer }
        raise DSLError, "unsupported component option #{unsupported}" if unsupported
        raise DSLError, "rotate must be 0, 90, 180, or 270" if attrs.key?(:rotate) && ![0, 90, 180, 270].include?(attrs[:rotate])
        raise DSLError, "mirror must be boolean" if attrs.key?(:mirror) && ![true, false].include?(attrs[:mirror])

        document.components << { ref: ref.to_s, type: type.to_s, value: value, pins: pins, at: at,
                                 attrs: attrs, unused: Array(attrs.delete(:unused)), location: source_location, step: @current_step }
      end

      def resistor(ref, value, **options)
        part(ref, :resistor, value, **options)
      end

      def capacitor(ref, value, **options)
        part(ref, :capacitor, value, **options)
      end

      def electrolytic(ref, value, **options)
        part(ref, :electrolytic, value, **options)
      end

      def diode(ref, value = nil, **options)
        part(ref, :diode, value, **options)
      end

      def led(ref, **options)
        part(ref, :led, nil, **options)
      end

      def transistor(ref, value = nil, **options)
        part(ref, :transistor, value, **options)
      end

      def pot(ref, value = nil, **options)
        part(ref, :pot, value, **options)
      end

      def button(ref, **options)
        part(ref, :button, nil, **options)
      end

      def ic(ref, value, **options)
        part(ref, value.to_s.downcase == "dip" ? :dip : value, nil, **options)
      end

      def wire(from, to, color: nil, id: nil, route: :straight, layer: nil, electrical: true, dashed: false)
        document.wires << { id: id&.to_s, from: from.to_s, to: to.to_s, color: color&.to_s,
                            route: route.to_s, layer: layer_names(layer), electrical: electrical != false,
                            dashed: !!dashed, location: source_location, step: @current_step }
      end

      def offboard(name, type, side: :left, at: nil, unused: [], **attrs)
        unsupported = attrs.keys.find { |key| %i[rotate mirror wire_layer].include?(key.to_sym) }
        raise DSLError, "unsupported component option #{unsupported}" if unsupported

        attrs[:at] = at if at
        document.components << { ref: name.to_s, type: type.to_s, attrs: attrs.merge(side: side.to_s),
                                 pins: nil, unused: Array(unused), location: source_location, offboard: true,
                                 step: @current_step }
      end

      def expect(strict: false, **options, &block)
        unknown = options.keys - [:when]
        raise DSLError, "unknown expect option #{unknown.first}" unless unknown.empty?
        at_state = options[:when]&.to_s
        raise DSLError, "expect when: must name a switch state" if options.key?(:when) && at_state.to_s.empty?
        entries = []
        previous = @expected
        @expected = entries
        instance_eval(&block)
        expectation = { strict: strict, entries: entries, location: source_location }
        expectation[:when] = at_state if at_state
        document.expectations << expectation
      ensure
        @expected = previous
      end

      def connected(*refs)
        raise DSLError, "connected must be inside expect" unless @expected

        @expected << { kind: "connected", refs: refs.map(&:to_s), location: source_location }
      end

      def connect(*refs, **options)
        raise DSLError, "connect is an intent assertion; use connected inside expect" if @expected
        raise DSLError, "connect requires exactly two references and does not place a wire" unless refs.length == 2
        raise DSLError, "connect references must be nonempty text" unless refs.all? { |ref| (ref.is_a?(String) || ref.is_a?(Symbol)) && !ref.to_s.empty? }
        unknown = options.keys - [:when]
        raise DSLError, "unknown connect option #{unknown.first}" unless unknown.empty?

        at_state = options[:when]&.to_s
        raise DSLError, "connect when: must name a switch state" if options.key?(:when) && at_state.to_s.empty?

        location = source_location
        expectation = { strict: false, entries: [{ kind: "connected", refs: refs.map(&:to_s), location: location }], location: location }
        expectation[:when] = at_state if at_state
        document.expectations << expectation
      end

      def isolated(*refs)
        raise DSLError, "isolated must be inside expect" unless @expected

        @expected << { kind: "isolated", refs: refs.map(&:to_s), location: source_location }
      end

      def expect_voltage(reference, range)
        measurement_expectation("voltage", reference, range)
      end

      def expect_current(reference, range)
        measurement_expectation("current", reference, range)
      end

      def lint_disable(rule_id, on: nil, reason: nil)
        document.lint_disables << { rule: rule_id.to_s, on: on&.to_s, reason: reason, location: source_location }
      end

      def method_missing(name, *_args, **_kwargs, &_block)
        suggestions = DidYouMean::SpellChecker.new(dictionary: METHODS).correct(name.to_s)
        hint = suggestions.empty? ? "" : "; did you mean #{suggestions.first.inspect}?"
        raise DSLError, "unknown DSL method #{name}#{hint}"
      end

      def respond_to_missing?(name, _include_private = false)
        METHODS.include?(name.to_s)
      end

      private

      def helper_name(value, kind)
        name = value.to_s
        raise DSLError, "invalid #{kind} name #{name.inspect}" unless value.is_a?(String) || value.is_a?(Symbol)
        raise DSLError, "invalid #{kind} name #{name.inspect}" unless /\A[A-Za-z][A-Za-z0-9_]*\z/.match?(name)

        name
      end

      def measurement_expectation(kind, reference, range)
        raise DSLError, "#{kind} expectation requires an inclusive range" unless range.is_a?(Range) && !range.exclude_end?

        limits = [Value.parse(range.begin), Value.parse(range.end)]
        raise DSLError, "#{kind} expectation range must be inclusive and ascending" unless limits.all?(&:finite?) && limits.first <= limits.last
        raise DSLError, "current expectation cannot be negative" if kind == "current" && limits.first.negative?

        entry = { kind: kind, refs: [reference.to_s], range: limits, location: source_location }
        if @expected
          @expected << entry
        else
          document.expectations << { strict: false, entries: [entry], location: source_location }
        end
      end

      def source_location
        loc = caller_locations(2, 12).find { |item| item.path && File.expand_path(item.path) != __FILE__ }
        SourceLocation.new(path: loc&.path, line: loc&.lineno)
      end

      def resolve_path(path)
        value = path.to_s
        File.expand_path(value, @base_dir)
      end

      def layer_names(value)
        return if value.nil?

        Array(value).map(&:to_s)
      end
    end

    def self.load_file(path, timeout: 10, source: nil)
      raise ArgumentError, "timeout must be positive" unless timeout.is_a?(Numeric) && timeout.finite? && timeout.positive?
      absolute = File.expand_path(path)
      builder = Builder.new(base_dir: File.dirname(absolute))
      builder.document.source_root = File.dirname(absolute)
      Timeout.timeout(timeout) { builder.instance_eval(source || File.read(absolute, encoding: "UTF-8"), absolute, 1) }
      builder.document
    rescue DSLError, ScriptError, StandardError, SystemExit, SystemStackError => e
      line = e.backtrace_locations&.find { |frame| frame.path == absolute }&.lineno
      location = e.is_a?(DSLError) && e.location || SourceLocation.new(path: path, line: line)
      detail = if e.is_a?(SystemExit)
        "exit is not allowed in a circuit file"
      elsif e.is_a?(Timeout::Error)
        "circuit evaluation timed out after #{timeout} seconds"
      else
        e.message
      end
      raise DSLError.new("#{location.path}#{":#{location.line}" if location.line}: #{detail}", location: location)
    end
  end
end
