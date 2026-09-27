# frozen_string_literal: true

module Breadkit
  module Formatter
    module_function

    def call(path)
      raise ArgumentError, "fmt supports .bk.yml, .bk.yaml, and .bk.toml files" unless path.end_with?(".bk.yml", ".bk.yaml", ".bk.toml")

      StructuredInput.load_file(path) # Validate the same fields accepted by the circuit loader.
      source = File.read(path, encoding: "UTF-8")
      if path.end_with?(".bk.toml")
        toml(Tomlrb.parse(source))
      else
        YAML.dump(YAML.safe_load(source, aliases: false), line_width: -1)
      end
    end

    def toml(data)
      root, sections = data.partition do |_key, value|
        !value.is_a?(Array) || value.empty? || !value.all? { |item| item.is_a?(Hash) }
      end
      lines = root.map { |key, value| "#{key_name(key)} = #{toml_value(value)}" }
      sections.each do |key, items|
        items.each do |item|
          lines << "" unless lines.empty?
          lines << "[[#{key_name(key)}]]"
          item.each { |field, value| lines << "#{key_name(field)} = #{toml_value(value)}" }
        end
      end
      "#{lines.join("\n")}\n"
    end

    def toml_value(value)
      case value
      when String then JSON.generate(value)
      when Integer then value.to_s
      when Float
        raise ArgumentError, "TOML cannot format nonfinite numbers" unless value.finite?
        value.to_s
      when TrueClass, FalseClass then value.to_s
      when Array then "[#{value.map { |item| toml_value(item) }.join(', ')}]"
      when Hash then "{#{value.map { |key, item| "#{key_name(key)} = #{toml_value(item)}" }.join(', ')}}"
      else raise ArgumentError, "TOML cannot format #{value.class}"
      end
    end

    def key_name(value)
      value.match?(/\A[A-Za-z0-9_-]+\z/) ? value : JSON.generate(value)
    end
  end
end
