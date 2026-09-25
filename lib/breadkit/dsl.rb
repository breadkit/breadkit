# frozen_string_literal: true

module Breadkit
  module DSL
    METHODS = %w[title board use_parts use_boards supply net part wire offboard expect lint_disable resistor capacitor electrolytic diode led transistor pot button ic connected isolated].freeze

    class Builder
      attr_reader :document

      def initialize(base_dir: Dir.pwd)
        @document = Document.new
        @expected = nil
        @base_dir = base_dir
      end

      def title(value)
        document.title = value.to_s
      end

      def board(type, **options)
        document.board = { type: type.to_s, options: options }
      end

      def use_parts(path)
        document.part_paths.concat(Dir.glob(resolve_path(path)))
      end

      def use_boards(path)
        document.board_paths.concat(Dir.glob(resolve_path(path)))
      end

      def supply(name, voltage:, plus:, minus:)
        document.supplies << { name: name.to_s, voltage: Value.parse(voltage), plus: plus.to_s,
                               minus: minus.to_s, location: source_location }
      end

      def net(name, *refs, at: nil, **options)
        if @expected
          @expected << { kind: "net", name: name.to_s, refs: (refs + [at] + options.values).compact.map(&:to_s), location: source_location }
        else
          document.labels << { name: name.to_s, at: at.to_s, location: source_location }
        end
      end

      def part(ref, type, value = nil, pins: nil, at: nil, **attrs)
        document.components << { ref: ref.to_s, type: type.to_s, value: value, pins: pins, at: at,
                                 attrs: attrs, unused: Array(attrs.delete(:unused)), location: source_location }
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

      def wire(from, to, color: nil, id: nil, route: :straight)
        document.wires << { id: id&.to_s, from: from.to_s, to: to.to_s, color: color&.to_s,
                            route: route.to_s, location: source_location }
      end

      def offboard(name, type, side: :left)
        document.components << { ref: name.to_s, type: type.to_s, attrs: { side: side.to_s },
                                 pins: nil, location: source_location, offboard: true }
      end

      def expect(strict: false, &block)
        entries = []
        previous = @expected
        @expected = entries
        instance_eval(&block)
        document.expectations << { strict: strict, entries: entries, location: source_location }
      ensure
        @expected = previous
      end

      def connected(*refs)
        @expected << { kind: "connected", refs: refs.map(&:to_s), location: source_location } if @expected
      end

      def isolated(*refs)
        @expected << { kind: "isolated", refs: refs.map(&:to_s), location: source_location } if @expected
      end

      def lint_disable(rule_id, on: nil, reason: nil)
        document.lint_disables << { rule: rule_id.to_s, on: on&.to_s, reason: reason, location: source_location }
      end

      def method_missing(name, *_args, **_kwargs, &_block)
        suggestions = DidYouMean::SpellChecker.new(dictionary: METHODS).correct(name.to_s)
        hint = suggestions.empty? ? "" : "; did you mean #{suggestions.first.inspect}?"
        raise DSLError, "unknown DSL method #{name}#{hint}"
      end

      def respond_to_missing?(_name, _include_private = false)
        true
      end

      private

      def source_location
        loc = caller_locations(2, 12).find { |item| item.path && !item.path.end_with?("/dsl.rb") }
        SourceLocation.new(path: loc&.path, line: loc&.lineno)
      end

      def resolve_path(path)
        value = path.to_s
        File.expand_path(value, @base_dir)
      end
    end

    def self.load_file(path)
      absolute = File.expand_path(path)
      builder = Builder.new(base_dir: File.dirname(absolute))
      builder.instance_eval(File.read(absolute), absolute, 1)
      builder.document
    rescue DSLError
      raise
    rescue SyntaxError, StandardError => e
      raise DSLError, "#{path}: #{e.message}"
    end
  end
end
