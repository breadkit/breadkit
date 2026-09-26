# frozen_string_literal: true

require "json"
require "yaml"
require "did_you_mean"

require_relative "breadkit/version"
require_relative "breadkit/value"
require_relative "breadkit/hole_id"
require_relative "breadkit/model"
require_relative "breadkit/board"
require_relative "breadkit/part_library"
require_relative "breadkit/dsl"
require_relative "breadkit/resolver"
require_relative "breadkit/analysis"
require_relative "breadkit/ir"
require_relative "breadkit/cli"

module Breadkit
  class Error < StandardError; end
  class DSLError < Error; end

  def self.load(path)
    path.end_with?(".json") ? IR::Reader.new.read_file(path) : Resolver.new.call(DSL.load_file(path))
  end
end
