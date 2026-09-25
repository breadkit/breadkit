# frozen_string_literal: true

module Breadkit
  class Value
    MULTIPLIERS = { "p" => 1e-12, "n" => 1e-9, "u" => 1e-6, "m" => 1e-3,
                    "R" => 1.0, "r" => 1.0, "k" => 1e3, "K" => 1e3,
                    "M" => 1e6, "G" => 1e9 }.freeze

    attr_reader :value

    def self.parse(input)
      return input.to_f if input.is_a?(Numeric)

      text = input.to_s.strip.gsub(/[ΩΩ]|ohm|[FfHhVv]/, "")
      if (match = /\A(\d+)([RrKkMm])(\d+)\z/.match(text))
        return (match[1].to_f + (match[3].to_f / (10**match[3].length))) * MULTIPLIERS.fetch(match[2])
      end
      match = /\A([+-]?(?:\d+(?:\.\d*)?|\.\d+))\s*([pnumkKMG]?)\z/.match(text)
      raise ArgumentError, "invalid value: #{input.inspect}" unless match

      match[1].to_f * MULTIPLIERS.fetch(match[2], 1.0)
    end

    def initialize(value)
      @value = self.class.parse(value)
      freeze
    end

    def to_s
      [[1e9, "G"], [1e6, "M"], [1e3, "k"], [1, ""], [1e-3, "m"], [1e-6, "u"], [1e-9, "n"]].each do |factor, suffix|
        scaled = value / factor
        return "#{format("%.3g", scaled)}#{suffix}Ω" if scaled.abs >= 1 && scaled.abs < 1000
      end
      "#{value}Ω"
    end
  end
end
