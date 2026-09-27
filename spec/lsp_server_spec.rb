# frozen_string_literal: true

require "stringio"
require "tmpdir"
require "uri"
require "breadkit/lsp_server"

RSpec.describe Breadkit::LSPServer do
  def frame(message)
    body = JSON.generate(message)
    "Content-Length: #{body.bytesize}\r\n\r\n#{body}"
  end

  def file_uri(path)
    normalized = path.tr("\\", "/")
    normalized = "/#{normalized}" if normalized.match?(/\A[A-Za-z]:\//)
    URI::File.build(path: normalized).to_s
  end

  def exchange(*messages, trusted_ruby: false, root: nil)
    input = StringIO.new(messages.map { |message| frame(message) }.join)
    output = StringIO.new
    described_class.new(input: input, output: output, root: root, trusted_ruby: trusted_ruby).run
    output.rewind
    results = []
    until output.eof?
      length = output.gets[/\AContent-Length: (\d+)/, 1].to_i
      output.gets
      results << JSON.parse(output.read(length))
    end
    results
  end

  let(:initialize_message) { { jsonrpc: "2.0", id: 1, method: "initialize", params: { capabilities: {} } } }

  it "synchronizes declarative buffers, reports errors, and inspects nets" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "example.bk.yml")
      uri = file_uri(path)
      valid = "board: mini\nsupplies:\n  - {name: USB, voltage: 5, plus: a1, minus: a2}\n"
      invalid = valid.sub("a1", "a999")
      messages = [initialize_message,
                  { jsonrpc: "2.0", method: "textDocument/didOpen", params: { textDocument: { uri: uri, version: 1, text: invalid } } },
                  { jsonrpc: "2.0", method: "textDocument/didChange", params: { textDocument: { uri: uri, version: 2 }, contentChanges: [{ text: valid }] } },
                  { jsonrpc: "2.0", id: 2, method: "textDocument/hover", params: { textDocument: { uri: uri }, position: { line: 2, character: 35 } } },
                  { jsonrpc: "2.0", id: 3, method: "textDocument/completion", params: { textDocument: { uri: uri }, position: { line: 2, character: 35 } } },
                  { jsonrpc: "2.0", id: 4, method: "shutdown" },
                  { jsonrpc: "2.0", method: "exit" }]
      results = exchange(*messages)
      expect(results.first.dig("result", "capabilities", "hoverProvider")).to eq(true)
      diagnostics = results.select { |item| item["method"] == "textDocument/publishDiagnostics" }
      expect(diagnostics.first.dig("params", "diagnostics").map { |item| item["code"] }).to include("invalid_hole")
      expect(diagnostics.last.dig("params", "diagnostics")).to eq([])
      expect(results.find { |item| item["id"] == 2 }.dig("result", "contents", "value")).to include("5")
      expect(results.find { |item| item["id"] == 3 }.dig("result").map { |item| item["label"] }).to include("a1")
    end
  end

  it "never evaluates Ruby buffers unless explicitly trusted" do
    Dir.mktmpdir do |dir|
      marker = File.join(dir, "executed")
      uri = file_uri(File.join(dir, "circuit.bk.rb"))
      source = "File.write(#{marker.inspect}, 'bad')\nboard :mini\n"
      messages = [initialize_message,
                  { jsonrpc: "2.0", method: "textDocument/didOpen", params: { textDocument: { uri: uri, version: 1, text: source } } },
                  { jsonrpc: "2.0", id: 2, method: "textDocument/hover", params: { textDocument: { uri: uri }, position: { line: 1, character: 3 } } },
                  { jsonrpc: "2.0", method: "exit" }]
      results = exchange(*messages)
      expect(File.exist?(marker)).to eq(false)
      expect(results.find { |item| item["id"] == 2 }["result"]).to be_nil
    end
  end

  it "completes component pins and named board holes in a buffer with unresolved references" do
    Dir.mktmpdir do |dir|
      uri = file_uri(File.join(dir, "boards.bk.yml"))
      source = "boards:\n  - {name: B1, type: mini}\n  - {name: B2, type: mini}\noffboard:\n  - {ref: UNO, type: arduino_uno}\nwires:\n  - {from: UNO.5, to: B2.a}\n"
      messages = [initialize_message,
                  { jsonrpc: "2.0", method: "textDocument/didOpen", params: { textDocument: { uri: uri, version: 1, text: source } } },
                  { jsonrpc: "2.0", id: 2, method: "textDocument/completion", params: { textDocument: { uri: uri }, position: { line: 6, character: 16 } } },
                  { jsonrpc: "2.0", id: 3, method: "textDocument/completion", params: { textDocument: { uri: uri }, position: { line: 6, character: 26 } } },
                  { jsonrpc: "2.0", method: "exit" }]
      results = exchange(*messages)
      expect(results.find { |item| item["id"] == 2 }["result"].map { |item| item["label"] }).to include("UNO.5V")
      expect(results.find { |item| item["id"] == 3 }["result"].map { |item| item["label"] }).to include("B2.a1")
    end
  end

  it "parses unsaved TOML safely and requires explicit trust for Ruby evaluation" do
    Dir.mktmpdir do |dir|
      uri = file_uri(File.join(dir, "circuit.bk.toml"))
      toml = "board = \"mini\"\n[[wires]]\nfrom = \"a1\"\nto = \"b1\"\n"
      results = exchange(initialize_message,
                         { jsonrpc: "2.0", method: "textDocument/didOpen", params: { textDocument: { uri: uri, version: 1, text: toml } } },
                         { jsonrpc: "2.0", method: "exit" })
      expect(results.find { |item| item["method"] == "textDocument/publishDiagnostics" }.dig("params", "diagnostics")).to eq([])

      marker = File.join(dir, "trusted")
      ruby_uri = file_uri(File.join(dir, "trusted.bk.rb"))
      source = "File.write(#{marker.inspect}, 'ok')\nboard :mini\n"
      exchange(initialize_message,
               { jsonrpc: "2.0", method: "textDocument/didOpen", params: { textDocument: { uri: ruby_uri, version: 1, text: source } } },
               { jsonrpc: "2.0", method: "exit" }, root: dir, trusted_ruby: true)
      expect(File.read(marker)).to eq("ok")
    end
  end

  it "rejects unsafe YAML and dependencies outside the workspace root" do
    Dir.mktmpdir do |dir|
      uri = file_uri(File.join(dir, "unsafe.bk.yml"))
      tagged = "--- !ruby/object:Object {}\n"
      results = exchange(initialize_message,
                         { jsonrpc: "2.0", method: "textDocument/didOpen", params: { textDocument: { uri: uri, version: 1, text: tagged } } },
                         { jsonrpc: "2.0", method: "exit" }, root: dir)
      error = results.find { |item| item["method"] == "textDocument/publishDiagnostics" }.dig("params", "diagnostics").first
      expect(error["code"]).to eq("invalid_source")

      Dir.mktmpdir do |outside|
        File.write(File.join(outside, "part.yml"), "id: x\npins: []\n")
        source = "board: mini\nuse_parts: [#{File.join(outside, 'part.yml').inspect}]\n"
        results = exchange(initialize_message,
                           { jsonrpc: "2.0", method: "textDocument/didOpen", params: { textDocument: { uri: uri, version: 1, text: source } } },
                           { jsonrpc: "2.0", method: "exit" }, root: dir)
        error = results.find { |item| item["method"] == "textDocument/publishDiagnostics" }.dig("params", "diagnostics").first
        expect(error["message"]).to include("outside the LSP root")
      end
    end
  end
end
