# frozen_string_literal: true

require "uri"
require_relative "../breadkit"

module Breadkit
  # A small LSP 3.18 server. Only full document synchronization is advertised.
  class LSPServer
    MAX_MESSAGE_BYTES = 8 * 1024 * 1024
    CIRCUIT_SUFFIXES = %w[.bk.yml .bk.yaml .bk.toml .bk.rb].freeze

    def initialize(input: $stdin, output: $stdout, root: nil, trusted_ruby: false)
      raise ArgumentError, "--trusted-ruby requires --root" if trusted_ruby && !root

      @input, @output = input, output
      @root = File.realpath(root) if root
      raise ArgumentError, "LSP root must be a directory" if @root && !File.directory?(@root)
      @trusted_ruby = trusted_ruby
      @documents = {}
      @running = true
    end

    def run
      while @running && (message = read_message)
        handle(message)
      end
    end

    private

    def read_message
      headers = {}
      while (line = @input.gets)
        break if line == "\r\n" || line == "\n"
        key, value = line.split(":", 2)
        headers[key.downcase] = value&.strip if key
      end
      return unless line

      size = Integer(headers.fetch("content-length"))
      raise ArgumentError, "LSP message exceeds 8 MiB" unless size.between?(1, MAX_MESSAGE_BYTES)

      body = @input.read(size)
      raise EOFError, "truncated LSP message" unless body && body.bytesize == size
      JSON.parse(body)
    end

    def send_message(message)
      body = JSON.generate({ jsonrpc: "2.0" }.merge(message))
      @output.write("Content-Length: #{body.bytesize}\r\n\r\n")
      @output.write(body)
      @output.flush
    end

    def reply(id, result)
      send_message(id: id, result: result)
    end

    def handle(message)
      method = message["method"]
      params = message["params"] || {}
      case method
      when "initialize"
        reply(message["id"], { capabilities: { textDocumentSync: 1, hoverProvider: true,
                                               completionProvider: { triggerCharacters: [".", ":", "\"", "'"] } },
                               serverInfo: { name: "breadkit", version: VERSION } })
      when "shutdown" then reply(message["id"], nil)
      when "exit" then @running = false
      when "textDocument/didOpen" then open_document(params.fetch("textDocument"))
      when "textDocument/didChange" then change_document(params)
      when "textDocument/didClose" then close_document(params.fetch("textDocument").fetch("uri"))
      when "textDocument/completion" then reply(message["id"], completion(params))
      when "textDocument/hover" then reply(message["id"], hover(params))
      else
        send_message(id: message["id"], error: { code: -32_601, message: "Method not found" }) if message.key?("id")
      end
    rescue StandardError => e
      send_message(id: message["id"], error: { code: -32_603, message: e.message }) if message.key?("id")
    end

    def open_document(document)
      uri = document.fetch("uri")
      path = file_path(uri)
      return unless path && CIRCUIT_SUFFIXES.any? { |suffix| path.end_with?(suffix) }

      @documents[uri] = { path: path, text: document.fetch("text"), version: document["version"] }
      analyze(uri)
    end

    def change_document(params)
      uri = params.fetch("textDocument").fetch("uri")
      document = @documents[uri]
      return unless document

      # Incremental changes are not advertised. Clients must send the full text.
      change = params.fetch("contentChanges").last
      return if change.key?("range")

      document[:text] = change.fetch("text")
      document[:version] = params["textDocument"]["version"]
      analyze(uri)
    end

    def close_document(uri)
      return unless @documents.delete(uri)

      send_message(method: "textDocument/publishDiagnostics", params: { uri: uri, diagnostics: [] })
    end

    def analyze(uri)
      document = @documents.fetch(uri)
      path, source = document.values_at(:path, :text)
      circuit = if path.end_with?(".bk.rb")
        Resolver.new.call(DSL.load_file(path, source: source, timeout: 2)) if @trusted_ruby && @root
      else
        parsed = StructuredInput.load_source(path, source)
        (parsed.part_paths + parsed.board_paths).each { |dependency| ensure_inside_root(dependency) } if @root
        PartLock.verify(parsed, path)
        Resolver.new.call(parsed)
      end
      document[:circuit] = circuit
      diagnostics = circuit ? circuit.diagnostics.map { |item| diagnostic(item, source) } : []
      publish(uri, document, diagnostics)
    rescue DSLError, ArgumentError, Psych::Exception => e
      document[:circuit] = nil
      location = e.respond_to?(:location) ? e.location : nil
      line = location&.line || (e.respond_to?(:line) && e.line) || 1
      publish(uri, document, [diagnostic_for("invalid_source", e.message, "error", line, source)])
    end

    def publish(uri, document, diagnostics)
      send_message(method: "textDocument/publishDiagnostics",
                   params: { uri: uri, version: document[:version], diagnostics: diagnostics })
    end

    def diagnostic(item, source)
      diagnostic_for(item.code, item.message, item.severity, item.location&.line, source)
    end

    def diagnostic_for(code, message, severity, line, source)
      index = [[line.to_i - 1, 0].max, source.lines.length - 1].min
      index = 0 if index.negative?
      end_character = source.lines[index].to_s.chomp.encode("UTF-16LE").bytesize / 2
      { range: { start: { line: index, character: 0 }, end: { line: index, character: end_character } },
        severity: { "error" => 1, "warning" => 2, "info" => 3 }.fetch(severity, 3),
        code: code, source: "breadkit", message: message }
    end

    def completion(params)
      document = @documents[params.dig("textDocument", "uri")]
      return [] unless document

      prefix = token_prefix(document[:text], params.fetch("position"))
      return [] if prefix.empty?

      circuit = document[:circuit]
      board = circuit&.board || board_from_source(document)
      candidates = board ? board.holes.keys + board.rail_ids : []
      if circuit
        circuit.components.each_value do |component|
          component.part.pins.each do |pin|
            ([pin["num"], pin["name"]] + Array(pin["aliases"])).compact.each do |name|
              candidates << "#{component.ref}.#{name}"
            end
          end
        end
        candidates.concat(circuit.labels.map(&:name))
      end
      candidates.uniq.grep(/\A#{Regexp.escape(prefix)}/i).first(200).map do |name|
        { label: name, kind: name.include?(".") ? 5 : 6 }
      end
    end

    def hover(params)
      document = @documents[params.dig("textDocument", "uri")]
      circuit = document && document[:circuit]
      return unless circuit && circuit.diagnostics.none? { |item| item.severity == "error" }

      reference = token_at(document[:text], params.fetch("position"))
      net = circuit.net_of(reference) if reference
      return unless net

      voltage = net.potential.nil? ? "unknown" : "#{net.potential} V"
      { contents: { kind: "markdown", value: "**#{reference}** · net `#{net.name}`\n\nPotential: #{voltage}" } }
    end

    def token_prefix(source, position)
      before = before_position(source, position)
      before[/[A-Za-z0-9_.+\-]+\z/] || ""
    end

    def token_at(source, position)
      line = source.lines[position.fetch("line")].to_s
      before = before_position(source, position)
      after = line[before.length..].to_s
      left = before[/[A-Za-z0-9_.+\-]+\z/].to_s
      right = after[/\A[A-Za-z0-9_.+\-]+/].to_s
      value = left + right
      value unless value.empty?
    end

    def before_position(source, position)
      line = source.lines[position.fetch("line")].to_s
      units = position.fetch("character")
      count = 0
      line.each_char.take_while do |char|
        count += char.encode("UTF-16LE").bytesize / 2
        count <= units
      end.join
    end

    def board_from_source(document)
      source = document[:text]
      type = if document[:path].end_with?(".bk.rb")
        source[/^\s*board\s+:(\w+)/, 1]
      elsif document[:path].end_with?(".toml")
        source[/^\s*board\s*=\s*["']([\w-]+)["']/, 1]
      else
        source[/^\s*board:\s*([\w-]+)/, 1]
      end
      Board.new(BoardDef.load(type)) if type
    rescue ArgumentError
      nil
    end

    def file_path(uri)
      parsed = URI.parse(uri)
      return unless parsed.scheme == "file"

      path = URI::DEFAULT_PARSER.unescape(parsed.path)
      path = path.delete_prefix("/") if Gem.win_platform? && path.match?(%r{\A/[A-Za-z]:/})
      expanded = File.expand_path(path)
      ensure_inside_root(expanded) if @root
      expanded
    rescue URI::InvalidURIError
      nil
    end

    def ensure_inside_root(path)
      expanded = File.expand_path(path)
      ancestor = expanded
      ancestor = File.dirname(ancestor) until File.exist?(ancestor)
      expanded = File.realpath(ancestor) + expanded.delete_prefix(ancestor)
      prefix = @root == File::SEPARATOR ? @root : "#{@root}#{File::SEPARATOR}"
      raise ArgumentError, "path is outside the LSP root" unless expanded.start_with?(prefix)
    end
  end
end
