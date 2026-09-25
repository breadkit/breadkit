# frozen_string_literal: true

module Breadkit
  class HoleId
    attr_reader :kind, :row, :col, :rail, :index, :ref, :pin

    def initialize(kind:, row: nil, col: nil, rail: nil, index: nil, ref: nil, pin: nil)
      @kind, @row, @col, @rail, @index, @ref, @pin = kind, row, col, rail, index, ref, pin
      freeze
    end

    def self.parse(value)
      text = value.to_s.strip
      if (m = /\A([a-j])(\d+)\z/i.match(text))
        col = m[2].to_i
        raise ArgumentError, "invalid hole: #{value}" unless col.positive?
        return new(kind: :terminal, row: m[1].downcase, col: col)
      end
      if (m = /\A([TB][+-])(\d*)\z/i.match(text))
        index = m[2].empty? ? nil : m[2].to_i
        raise ArgumentError, "invalid hole: #{value}" if index == 0
        return new(kind: :rail, rail: m[1].upcase, index: index)
      end
      if (m = /\A([A-Za-z][\w-]*)\.([A-Za-z0-9_+-]+)\z/.match(text))
        return new(kind: :pin, ref: m[1], pin: m[2])
      end
      raise ArgumentError, "invalid hole or pin reference: #{value.inspect}"
    end

    def to_s
      case kind
      when :terminal then "#{row}#{col}"
      when :rail then "#{rail}#{index}"
      else "#{ref}.#{pin}"
      end
    end
  end
end
