# frozen_string_literal: true

require "rexml/document"
require "tmpdir"

RSpec.describe Breadkit::Render::SvgRenderer do
  let(:circuit) { Breadkit.load(File.expand_path("../../../examples/01_led_button.bk.rb", __dir__)) }

  it "renders deterministic, well-formed SVG with escaped text and layers" do
    circuit.instance_variable_set(:@title, "R&D <LED>")
    svg = described_class.new.render(circuit, legend: true, show_nets: true)
    expect { REXML::Document.new(svg) }.not_to raise_error
    expect(svg).to include("R&amp;D &lt;LED&gt;", "id=\"board\"", "id=\"wires\"", "data-hole=\"a10\"")
    expect(described_class.new.render(circuit, legend: true, show_nets: true)).to eq(svg)
  end

  it "adds a bounded legend with each net name and representative wire color" do
    svg = described_class.new.render(circuit, legend: true)
    document = REXML::Document.new(svg)
    view_box = document.root.attributes["viewBox"].split.map(&:to_f)
    legend = document.root.elements["g[@id='legend']"]

    expect(view_box).to have_attributes(length: 4)
    expect(legend.elements.to_a("text").map(&:text)).to include("VCC", "GND", "N1", "N2")
    expect(legend.elements.to_a("line").map { |item| item.attributes["stroke"] }).to include("red", "black")
    expect(legend.elements.to_a("text").all? { |item| item.attributes["y"].to_f <= view_box[1] + view_box[3] }).to be(true)
  end

  it "can render an empty board and every bundled board size" do
    %w[full half mini].each do |type|
      builder = Breadkit::DSL::Builder.new
      builder.instance_eval("board :#{type}", "empty.bk.rb", 1)
      svg = described_class.new.render(Breadkit::Resolver.new.call(builder.document))
      expect(REXML::Document.new(svg).root.attributes["viewBox"]).not_to be_nil
    end
  end

  it "overlays lint targets with markers and messages" do
    annotations = [{ "rule" => "Electrical/ShortCircuit", "severity" => "error", "message" => "short",
                     "targets" => { "holes" => ["a10"], "wires" => ["W1"], "components" => ["SW1"] } }]
    svg = described_class.new.render(circuit, annotations: annotations)
    expect(svg).to include("id=\"annotations\"", "#d62728", "1. short")
    expect { REXML::Document.new(svg) }.not_to raise_error
  end

  it "uses automatic wire colors and reads annotations from bklint JSON" do
    builder = Breadkit::DSL::Builder.new
    builder.instance_eval('board :mini; wire "a1", "a2"', "wire.bk.rb", 1)
    wire_svg = described_class.new.render(Breadkit::Resolver.new.call(builder.document))
    expect(wire_svg).to include("stroke=\"#d62728\"")

    input = File.expand_path("../../../examples/bad/short_circuit.bk.rb", __dir__)
    json = { schema_version: 1, files: [{ path: input, offenses: [{ rule: "Electrical/ShortCircuit", severity: "error",
      message: "short circuit", targets: { holes: ["a10"], wires: ["W1"] } }] }] }
    Dir.mktmpdir do |directory|
      annotations_path, output_path = File.join(directory, "lint.json"), File.join(directory, "review.svg")
      File.write(annotations_path, JSON.generate(json))
      status = Breadkit::Render::CLI.new.run([input, "--annotations", annotations_path, "-o", output_path])
      expect(status).to eq(0)
      expect(File.read(output_path)).to include("1. short circuit", "#d62728")
    end
  end

  it "renders offboard module pins and connects their wires" do
    builder = Breadkit::DSL::Builder.new
    builder.instance_eval('board :half; offboard :UNO, "arduino_uno"; wire "UNO.D13", "a1"', "sample.bk.rb", 1)
    circuit = Breadkit::Resolver.new.call(builder.document)
    svg = described_class.new.render(circuit)

    expect(svg).to include("Arduino Uno", "UNO.D13", "id=\"offboard\"")
    expect(svg.scan("<path ").length).to eq(1)
  end

  it "maps resistor values to the expected four-band colors" do
    renderer = described_class.new
    colors = %w[#000000 #8b4513 #ff0000 #ff8c00 #ffff00 #008000 #0000ff #800080 #808080 #ffffff]
    expect(renderer.send(:resistor_bands, "220")).to eq([colors[2], colors[2], colors[1], "#d4af37"])
    expect(renderer.send(:resistor_bands, "330")).to eq([colors[3], colors[3], colors[1], "#d4af37"])
    expect(renderer.send(:resistor_bands, "10k")).to eq([colors[1], colors[0], colors[3], "#d4af37"])
  end

  it "matches empty-board and example SVG snapshots" do
    %w[full half mini].each do |type|
      builder = Breadkit::DSL::Builder.new
      builder.instance_eval("board :#{type}", "empty.bk.rb", 1)
      circuit = Breadkit::Resolver.new.call(builder.document)
      expect_svg_snapshot("empty_#{type}", described_class.new.render(circuit))
    end

    %w[01_led_button 02_555_blinker].each do |name|
      path = File.expand_path("../../../examples/#{name}.bk.rb", __dir__)
      expect_svg_snapshot(name, described_class.new.render(Breadkit.load(path)))
    end
  end
end

RSpec.describe Breadkit::Render::CLI do
  it "rejects output extensions that conflict with the requested format" do
    expect(described_class.new.run(["-o", "diagram.png", "-f", "svg", "input.bk.rb"]))
      .to eq(2)
  end

  it "rasterizes to PNG and JPEG when optional system backends are installed" do
    svg = Breadkit::Render::SvgRenderer.new.render(Breadkit.load(File.expand_path("../../../examples/01_led_button.bk.rb", __dir__)))
    rasterizer = Breadkit::Render::Rasterizer.new
    expect(rasterizer.rasterize(svg, format: "png")).to start_with("\x89PNG\r\n\x1a\n".b)
    expect(rasterizer.rasterize(svg, format: "jpeg")).to start_with("\xFF\xD8".b)
  rescue Breadkit::Render::Error => e
    skip e.message
  end

  it "validates raster options before selecting a backend" do
    rasterizer = Breadkit::Render::Rasterizer.new
    expect { rasterizer.rasterize("", format: "gif") }.to raise_error(Breadkit::Render::Error, /unsupported raster format/)
    expect { rasterizer.rasterize("", format: "png", scale: 0) }.to raise_error(Breadkit::Render::Error, /scale/)
    expect { rasterizer.rasterize("", format: "png", scale: Float::INFINITY) }.to raise_error(Breadkit::Render::Error, /scale/)
    expect { rasterizer.rasterize("", format: "png", quality: 101) }.to raise_error(Breadkit::Render::Error, /quality/)
    expect { rasterizer.rasterize("", format: "png", backend: "unknown") }.to raise_error(Breadkit::Render::Error, /unsupported raster backend/)
  end

  it "parses white and hex JPEG backgrounds for libvips" do
    rasterizer = Breadkit::Render::Rasterizer.new
    expect(rasterizer.send(:color, "white")).to eq([255, 255, 255])
    expect(rasterizer.send(:color, "#123")).to eq([17, 34, 51])
    expect(rasterizer.send(:color, "#123456")).to eq([18, 52, 86])
    expect { rasterizer.send(:color, "not a color") }.to raise_error(Breadkit::Render::Error, /background color/)
  end

  it "produces valid raster files through each available backend" do
    rasterizer = Breadkit::Render::Rasterizer.new
    svg = '<svg xmlns="http://www.w3.org/2000/svg" width="1" height="1"/>'
    signatures = { "png" => "\x89PNG\r\n\x1a\n".b, "jpeg" => "\xFF\xD8".b }

    [["rsvg", "png"], ["vips", "png"], ["vips", "jpeg"], ["magick", "png"], ["magick", "jpeg"]].each do |backend, format|
      next unless rasterizer.send(:supports?, backend, format)

      output = rasterizer.rasterize(svg, format: format, backend: backend)
      expect(output).to start_with(signatures.fetch(format))
    end

    if rasterizer.send(:supports?, "vips", "jpeg")
      jpeg = rasterizer.rasterize(svg, format: "jpeg", backend: "vips")
      expect(Vips::Image.jpegload_buffer(jpeg).getpoint(0, 0)).to eq([255.0, 255.0, 255.0])
    end
  end
end
