# frozen_string_literal: true

module Breadkit
  class Value
    QUALIFIER = /\s+(\d+(?:\.\d+)?%|\d+(?:\.\d+)?(?:\/\d+(?:\.\d+)?)?[WV])\z/i
    MULTIPLIERS = { "p" => 1e-12, "n" => 1e-9, "u" => 1e-6, "m" => 1e-3,
                    "R" => 1.0, "r" => 1.0, "k" => 1e3, "K" => 1e3,
                    "M" => 1e6, "G" => 1e9 }.freeze
    PREFIXES = [[1e9, "G"], [1e6, "M"], [1e3, "k"], [1, ""], [1e-3, "m"],
                [1e-6, "u"], [1e-9, "n"], [1e-12, "p"]].freeze

    attr_reader :value, :unit

    def self.parse(input)
      return input.to_f if input.is_a?(Numeric)

      text = split_spec(input).first.sub(/(?:Ω|Ω|ohm|[FfHhVv])\z/i, "").tr("µμ", "uu")
      if (match = /\A(\d*)([pnuRrmkKMG])(\d+)\z/.match(text))
        whole = match[1].empty? ? 0 : match[1].to_i
        return (whole + match[3].to_f / (10**match[3].length)) * MULTIPLIERS.fetch(match[2])
      end
      match = /\A([+-]?(?:\d+(?:\.\d*)?|\.\d+))\s*([pnumrRkKMG]?)\z/.match(text)
      raise ArgumentError, "invalid value: #{input.inspect}" unless match

      match[1].to_f * MULTIPLIERS.fetch(match[2], 1.0)
    end

    def self.tolerance(input)
      suffix = split_spec(input).last.find { |item| item.end_with?("%") }
      suffix && suffix.to_f / 100.0
    end

    def self.power_rating(input)
      suffix = split_spec(input).last.find { |item| item.upcase.end_with?("W") }
      return unless suffix

      quantity = suffix[0...-1]
      quantity.include?("/") ? quantity.split("/").map(&:to_f).reduce(:/) : quantity.to_f
    end

    def self.voltage_rating(input)
      suffix = split_spec(input).last.find { |item| item.upcase.end_with?("V") }
      suffix&.to_f
    end

    def self.split_spec(input)
      base = input.to_s.strip
      qualifiers = []
      while (match = QUALIFIER.match(base))
        qualifiers.unshift(match[1])
        base = base[0...match.begin(0)]
      end
      kinds = qualifiers.map { |item| item[-1].upcase }
      raise ArgumentError, "duplicate value qualifier: #{input.inspect}" unless kinds.uniq == kinds
      qualifiers.each do |item|
        quantity = item[0...-1]
        numbers = quantity.split("/").map(&:to_f)
        invalid = numbers.any? { |number| !number.finite? || !number.positive? } || (item.end_with?("%") && numbers.first > 100)
        raise ArgumentError, "invalid value qualifier: #{item}" if invalid
      end
      [base, qualifiers]
    end

    def initialize(value, category: nil)
      explicit = self.class.split_spec(value).first[/\A.*?(Ω|Ω|ohm|[FfHhVv])\z/i, 1]
      @unit = explicit&.then { |suffix| %w[Ω Ω ohm].include?(suffix.downcase) ? "Ω" : suffix.upcase } ||
              { resistor: "Ω", capacitor: "F", electrolytic: "F", inductor: "H", supply: "V" }.fetch(category&.to_sym, "")
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
