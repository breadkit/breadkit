# frozen_string_literal: true

require "digest"
require "pathname"

module Breadkit
  # Pins local part and board definition files used by a circuit.
  class PartLock
    FORMAT = 1
    SUFFIXES = %w[.bk.rb .bk.yml .bk.yaml .bk.toml].freeze

    def self.write(path)
      circuit_path = File.expand_path(path)
      raise ArgumentError, "lock supports .bk.rb, .bk.yml, .bk.yaml, and .bk.toml circuits" unless circuit_file?(circuit_path)

      document = if circuit_path.end_with?(".bk.rb")
        DSL.load_file(circuit_path)
      else
        StructuredInput.load_file(circuit_path)
      end
      file = lock_path(circuit_path)
      data = File.file?(file) ? read(file) : { "version" => FORMAT, "circuits" => {} }
      data.fetch("circuits")[File.basename(circuit_path)] = entry(document, circuit_path)
      data["circuits"] = data.fetch("circuits").sort.to_h
      File.write(file, "#{JSON.pretty_generate(data)}\n")
      file
    end

    def self.verify(document, path)
      circuit_path = File.expand_path(path)
      return unless circuit_file?(circuit_path)

      file = lock_path(circuit_path)
      return unless File.file?(file)

      expected = read(file).fetch("circuits")[File.basename(circuit_path)]
      raise DSLError, "breadkit.lock has no entry for #{File.basename(circuit_path)}; run breadkit lock FILE" unless expected
      raise DSLError, "breadkit.lock version mismatch for #{File.basename(circuit_path)}; run breadkit lock FILE" unless expected.fetch("breadkit") == VERSION

      current = entry(document, circuit_path)
      %w[parts boards].each do |kind|
        saved, actual = expected.fetch(kind), current.fetch(kind)
        saved_paths, actual_paths = saved.map { |item| item.fetch("path") }, actual.map { |item| item.fetch("path") }
        raise DSLError, "breadkit.lock definition set changed for #{kind}; run breadkit lock FILE" unless saved_paths == actual_paths

        saved.zip(actual).each do |before, after|
          next if before.fetch("sha256") == after.fetch("sha256")

          raise DSLError, "breadkit.lock checksum mismatch for #{after.fetch('path')}; run breadkit lock FILE"
        end
      end
    end

    def self.lock_path(path)
      File.join(File.dirname(File.expand_path(path)), "breadkit.lock")
    end

    def self.circuit_file?(path)
      SUFFIXES.any? { |suffix| path.end_with?(suffix) }
    end
    private_class_method :circuit_file?

    def self.entry(document, path)
      base = Pathname.new(File.dirname(path))
      { "breadkit" => VERSION, "parts" => records(document.part_paths, base),
        "boards" => records(document.board_paths, base) }
    end
    private_class_method :entry

    def self.records(paths, base)
      paths.uniq.map do |path|
        absolute = Pathname.new(File.expand_path(path))
        { "path" => absolute.relative_path_from(base).to_s.tr("\\", "/"), "sha256" => Digest::SHA256.file(absolute).hexdigest }
      rescue ArgumentError
        raise DSLError, "local definitions must share a filesystem with the circuit"
      end.sort_by { |item| item.fetch("path") }
    end
    private_class_method :records

    def self.read(path)
      raise DSLError, "invalid breadkit.lock: file exceeds 1 MiB" if File.size(path) > 1024 * 1024

      data = JSON.parse(File.read(path, encoding: "UTF-8"))
      unless data.is_a?(Hash) && data.keys.sort == %w[circuits version] && data["version"] == FORMAT && data["circuits"].is_a?(Hash)
        raise DSLError, "invalid breadkit.lock: unsupported format"
      end
      data.fetch("circuits").each_value do |item|
        unless item.is_a?(Hash) && item.keys.sort == %w[boards breadkit parts] && item["breadkit"].is_a?(String) &&
               %w[parts boards].all? { |key| valid_records?(item[key]) }
          raise DSLError, "invalid breadkit.lock: malformed circuit entry"
        end
      end
      data
    rescue JSON::ParserError => e
      raise DSLError, "invalid breadkit.lock: #{e.message}"
    end
    private_class_method :read

    def self.valid_records?(items)
      items.is_a?(Array) && items.all? do |item|
        item.is_a?(Hash) && item.keys.sort == %w[path sha256] && item["path"].is_a?(String) &&
          !item["path"].empty? && item["sha256"].is_a?(String) && item["sha256"].match?(/\A[0-9a-f]{64}\z/)
      end
    end
    private_class_method :valid_records?
  end
end
