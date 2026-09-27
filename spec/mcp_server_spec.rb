# frozen_string_literal: true

require "open3"
require "tmpdir"
require "timeout"
require "breadkit/mcp_server"

RSpec.describe "MCP stdio server" do
  def request(stdin, stdout, id, method, params = nil)
    message = { jsonrpc: "2.0", id: id, method: method }
    message[:params] = params if params
    stdin.puts(JSON.generate(message))
    Timeout.timeout(10) { JSON.parse(stdout.gets) }
  end

  def tool(stdin, stdout, id, name, arguments)
    response = request(stdin, stdout, id, "tools/call", { name: name, arguments: arguments })
    response.fetch("result") { raise response.inspect }
  end

  def with_server(root)
    repo = File.expand_path("..", __dir__)
    executable = File.join(repo, "exe/breadkit-mcp")
    Open3.popen3(RbConfig.ruby, "-I#{File.join(repo, 'lib')}", executable, "--root", root, chdir: repo) do |stdin, stdout, stderr, process|
      initialized = request(stdin, stdout, 1, "initialize", {
        protocolVersion: "2025-11-25", capabilities: {}, clientInfo: { name: "breadkit-spec", version: "1.0" }
      })
      expect(initialized.dig("result", "capabilities")).to have_key("tools")
      stdin.puts(JSON.generate(jsonrpc: "2.0", method: "notifications/initialized"))
      yield stdin, stdout
    ensure
      stdin.close unless stdin.closed?
      Timeout.timeout(10) { process.value }
      expect(stderr.read).to be_empty
    end
  end

  it "lists read-only tools and resolves, inspects, and exports a declarative circuit" do
    Dir.mktmpdir do |root|
      path = File.join(root, "example.bk.yml")
      File.write(path, <<~YAML)
        board: mini
        supplies:
          - {name: BAT, voltage: 5, plus: a1, minus: a5}
        parts:
          - {ref: R1, type: resistor, value: "1k", pins: [b1, a3]}
      YAML
      with_server(root) do |stdin, stdout|
        listed = request(stdin, stdout, 2, "tools/list").fetch("result").fetch("tools")
        names = listed.map { |item| item.fetch("name") }
        expect(names).to contain_exactly("breadkit_resolve", "breadkit_nets", "breadkit_ir")
        expect(listed).to all(include("annotations" => include("readOnlyHint" => true)))

        resolved = tool(stdin, stdout, 3, "breadkit_resolve", { path: "example.bk.yml" })
        expect(resolved.fetch("isError")).to be(false)
        expect(resolved.dig("structuredContent", "valid")).to be(true)
        expect(resolved.dig("structuredContent", "components")).to eq(["R1"])

        nets = tool(stdin, stdout, 4, "breadkit_nets", { path: "example.bk.yml" })
        expect(nets.fetch("isError")).to be(false)
        expect(nets.dig("structuredContent", "nets")).to include(include("members" => include("R1.1")))

        unknown_state = tool(stdin, stdout, 6, "breadkit_nets", { path: "example.bk.yml", state: "SW1" })
        expect(unknown_state.fetch("isError")).to be(true)

        ir = tool(stdin, stdout, 5, "breadkit_ir", { path: "example.bk.yml" })
        expect(ir.fetch("isError")).to be(false)
        expect(ir.dig("structuredContent", "schema_version")).to eq(1)
        expect(ir.dig("structuredContent", "components", 0, "ref")).to eq("R1")
      end
    end
  end

  it "rejects executable Ruby and paths outside the configured root" do
    Dir.mktmpdir do |root|
      marker = File.join(root, "executed")
      File.write(File.join(root, "unsafe.bk.rb"), "File.write(#{marker.inspect}, 'executed')\n")
      with_server(root) do |stdin, stdout|
        ruby_result = tool(stdin, stdout, 2, "breadkit_resolve", { path: "unsafe.bk.rb" })
        expect(ruby_result.fetch("isError")).to be(true)
        expect(ruby_result.fetch("content").first.fetch("text")).to match(/YAML, TOML, or JSON IR/)
        outside = tool(stdin, stdout, 3, "breadkit_ir", { path: "../outside.bk.yml" })
        expect(outside.fetch("isError")).to be(true)
      end
      expect(File).not_to exist(marker)
    end
  end

  it "accepts TOML and IR inputs while reporting invalid circuit diagnostics" do
    Dir.mktmpdir do |root|
      toml = File.join(root, "sample.bk.toml")
      File.write(toml, <<~TOML)
        board = "mini"
        [[parts]]
        ref = "R1"
        type = "resistor"
        value = "1k"
        pins = ["a1", "a3"]
      TOML
      service = Breadkit::MCPServer.new(root: root).server
      exported = service.tools.fetch("breadkit_ir").call(path: "sample.bk.toml")
      expect(exported.error?).to be(false)
      File.write(File.join(root, "sample.json"), JSON.generate(exported.structured_content))
      resolved = service.tools.fetch("breadkit_resolve").call(path: "sample.json")
      expect(resolved.structured_content.fetch(:components)).to eq(["R1"])

      File.write(File.join(root, "broken.bk.yml"), "board: mini\nwires:\n  - {from: z99, to: a1}\n")
      invalid = service.tools.fetch("breadkit_resolve").call(path: "broken.bk.yml")
      expect(invalid.structured_content.fetch(:valid)).to be(false)
      expect(invalid.structured_content.fetch(:diagnostics).map { |item| item.fetch(:code) }).to include("invalid_hole")
      expect(service.tools.fetch("breadkit_ir").call(path: "broken.bk.yml").error?).to be(true)
    end
  end

  it "rejects project definitions that escape the configured root" do
    Dir.mktmpdir do |parent|
      root = File.join(parent, "project")
      Dir.mkdir(root)
      File.write(File.join(parent, "external.yml"), "id: external\npins: []\n")
      File.write(File.join(root, "circuit.bk.yml"), "board: mini\nuse_parts: ../external.yml\n")
      service = Breadkit::MCPServer.new(root: root).server
      result = service.tools.fetch("breadkit_resolve").call(path: "circuit.bk.yml")
      expect(result.error?).to be(true)
      expect(result.content.first.fetch(:text)).to include("outside the MCP root")
    end
  end
end
