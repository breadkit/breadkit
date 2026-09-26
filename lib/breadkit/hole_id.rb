# frozen_string_literal: true

module Breadkit
  class HoleId
    attr_reader :kind, :row, :col, :rail, :index, :ref, :pin

    def initialize(kind:, row: nil, col: nil, rail: nil, index: nil, ref: nil, pin: nil)
      @kind, @row, @col, @rail, @index, @ref, @pin = kind, row, col, rail, index, ref, pin
      freeze
    end

    def self.parse(value, board: nil)
      text = value.to_s.strip
      rows = board ? board.terminal_rows : ('a'..'j').to_a
      rails = board ? board.rail_ids : %w[T+ T- B+ B-]
      rows.sort_by { |row| -row.length }.each do |row|
        m = /\A(#{Regexp.escape(row)})(\d+)\z/i.match(text)
        next unless m

        col = m[2].to_i
        raise ArgumentError, "invalid hole: #{value}" unless col.positive?
        return new(kind: :terminal, row: row, col: col)
      end
      rails.sort_by { |rail| -rail.length }.each do |rail|
        m = /\A(#{Regexp.escape(rail)})(\d*)\z/i.match(text)
        next unless m

        index = m[2].empty? ? nil : m[2].to_i
        raise ArgumentError, "invalid hole: #{value}" if index == 0
        return new(kind: :rail, rail: rail, index: index)
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
