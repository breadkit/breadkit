# frozen_string_literal: true

require "breadkit"
require "cgi"
require "open3"
require_relative "render/version"
require_relative "render/svg_renderer"
require_relative "render/rasterizer"
require_relative "render/cli"

module Breadkit
  module Render
    class Error < StandardError; end
  end
end
