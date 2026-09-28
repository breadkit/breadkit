# frozen_string_literal: true

require "tmpdir"
require "breadkit/mcp_server"

source = <<~YAML
  board: mini
  supplies:
    - {name: BAT, voltage: 5, plus: a1, minus: a5}
  parts:
    - {ref: D1, type: led, pins: {anode: b1, cathode: c5}}
YAML

Dir.mktmpdir do |root|
  tools = Breadkit::MCPServer.new(root: root).server.tools
  call = lambda do |name|
    response = tools.fetch(name).call(format: "yaml", source: source)
    raise "#{name}: #{response.content.inspect}" if response.error?

    response.structured_content
  end

  raise "draft did not resolve" unless call.call("breadkit_resolve_source").fetch(:valid)

  lint = call.call("breadkit_lint_source")
  raise "draft path was not normalized" unless lint.fetch("files").first.fetch("path") == "draft.bk.yml"
  rules = lint.fetch("files").first.fetch("offenses").map { |item| item.fetch("rule") }
  raise "missing LED safety finding" unless rules.include?("Electrical/MissingSeriesResistor")

  svg = call.call("breadkit_render_source").fetch(:svg)
  raise "missing static SVG" unless svg.include?("<svg") && !svg.include?("<script")
  raise "draft tools wrote a file" unless Dir.children(root).empty?
end

puts "MCP draft resolve, lint, and render succeeded"
