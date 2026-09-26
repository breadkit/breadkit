# frozen_string_literal: true

module Breadkit
  class Value
    MULTIPLIERS = { "p" => 1e-12, "n" => 1e-9, "u" => 1e-6, "m" => 1e-3,
                    "R" => 1.0, "r" => 1.0, "k" => 1e3, "K" => 1e3,
                    "M" => 1e6, "G" => 1e9 }.freeze
    PREFIXES = [[1e9, "G"], [1e6, "M"], [1e3, "k"], [1, ""], [1e-3, "m"],
                [1e-6, "u"], [1e-9, "n"], [1e-12, "p"]].freeze

    attr_reader :value, :unit

    def self.parse(input)
      return input.to_f if input.is_a?(Numeric)

      text = input.to_s.strip.sub(/(?:Ω|Ω|ohm|[FfHhVv])\z/i, "").tr("µμ", "uu")
      if (match = /\A(\d*)([pnuRrmkKMG])(\d+)\z/.match(text))
        whole = match[1].empty? ? 0 : match[1].to_i
        return (whole + match[3].to_f / (10**match[3].length)) * MULTIPLIERS.fetch(match[2])
      end
      match = /\A([+-]?(?:\d+(?:\.\d*)?|\.\d+))\s*([pnumrRkKMG]?)\z/.match(text)
      raise ArgumentError, "invalid value: #{input.inspect}" unless match

      match[1].to_f * MULTIPLIERS.fetch(match[2], 1.0)
    end

    def initialize(value)
      @unit = value.to_s.strip[/\A.*?(Ω|Ω|ohm|[FfHhVv])\z/i, 1]&.then { |suffix| %w[Ω Ω ohm].include?(suffix.downcase) ? "Ω" : suffix.upcase } || "Ω"
      @value = self.class.parse(value)
      freeze
    end

    def to_s
      return "0#{unit}" if value.zero?

      PREFIXES.each_with_index do |(factor, suffix), index|
        scaled = value / factor
        next unless scaled.abs >= 1 && (scaled.abs < 1000 || index.zero?)

        rounded = format("%.3g", scaled)
        if rounded.to_f.abs >= 1000 && index.positive?
          higher_factor, higher_suffix = PREFIXES[index - 1]
          return "#{format('%.3g', value / higher_factor)}#{higher_suffix}#{unit}"
        end
        return "#{rounded}#{suffix}#{unit}"
      end
      "#{value}#{unit}"
    end
  end
end
