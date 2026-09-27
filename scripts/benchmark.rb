# frozen_string_literal: true

require "breadkit"
require "breadkit/lint"
require "breadkit/render"

def measure
  start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  yield
  Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
end

source = ["board :full"]
20.times do |pair|
  ("a".."e").each do |column|
    row = (pair * 2) + 1
    source << %(resistor :R#{(pair * 5) + column.ord - 96}, "330", pins: %w[#{column}#{row} #{column}#{row + 1}])
  end
end
200.times do |index|
  column = ("f".."j").to_a[index % 5]
  row = (index / 5) + 1
  rail = %w[T+ T- B+ B-][index / 50]
  source << %(wire "#{column}#{row}", "#{rail}#{(index % 50) + 1}")
end
[41, 42, 45, 46, 49, 50, 53, 54, 57, 58].each_with_index do |row, index|
  source << %(button :SW#{index + 1}, at: "e#{row}")
end

document = Breadkit::DSL.load_file("benchmark.bk.rb", source: source.join("\n"))
circuit = nil
resolution = measure { circuit = Breadkit::Resolver.new.call(document) }
network = measure { circuit.states("single").each { |state| circuit.nets(state) } }
abort "benchmark circuit has errors" if circuit.diagnostics.any? { |item| item.severity == "error" }
abort "benchmark circuit size changed" unless circuit.components.size == 110 && circuit.wires.size == 200

lint_result = nil
linter = Breadkit::Lint::Engine.new
lint = measure do
  lint_result = linter.run(["benchmark.bk.rb"], source: source.join("\n"))
end
abort "lint failed to inspect benchmark circuit" if linter.fatal?(lint_result)
svg = nil
render = measure { svg = Breadkit::Render::SvgRenderer.new.render(circuit) }
abort "render produced no SVG" unless svg.include?("<svg")

puts "110 components (100 resistors, 10 switches), 200 wires, single switch states"
puts "resolve: #{resolution.round(3)}s, states/nets: #{network.round(3)}s, lint: #{lint.round(3)}s, SVG: #{render.round(3)}s"
abort "performance regression: analysis > 2s or SVG > 1s" if resolution + network > 2 || render > 1
