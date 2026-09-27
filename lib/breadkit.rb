# frozen_string_literal: true

require "json"
require "yaml"
require "did_you_mean"

require_relative "breadkit/version"
require_relative "breadkit/value"
require_relative "breadkit/color"
require_relative "breadkit/hole_id"
require_relative "breadkit/model"
require_relative "breadkit/board"
require_relative "breadkit/part_library"
require_relative "breadkit/dsl"
require_relative "breadkit/structured_input"
require_relative "breadkit/part_lock"
require_relative "breadkit/formatter"
require_relative "breadkit/resolver"
require_relative "breadkit/analysis"
require_relative "breadkit/wire_suggestions"
require_relative "breadkit/jumper_kit"
require_relative "breadkit/dc_analysis"
require_relative "breadkit/ir"
require_relative "breadkit/exporters"
require_relative "breadkit/cli"

module Breadkit
  class Error < StandardError; end
  class DSLError < Error
    attr_reader :location

    def initialize(message, location: nil)
      super(message)
      @location = location
    end
  end

  def self.load(path, timeout: 10)
    return IR::Reader.new.read_file(path) if path.end_with?(".json")

    document = if path.end_with?(".bk.yml", ".bk.yaml", ".bk.toml")
      StructuredInput.load_file(path)
    else
      DSL.load_file(path, timeout: timeout)
    end
    PartLock.verify(document, path)
    Resolver.new.call(document)
  end
end
