# frozen_string_literal: true

require "mcp"
require_relative "../breadkit"

module Breadkit
  class MCPServer
    EXTENSIONS = %w[.bk.yml .bk.yaml .bk.toml .json].freeze
    MAX_INPUT_BYTES = 8 * 1024 * 1024

    def initialize(root: Dir.pwd)
      @root = File.realpath(root)
      raise ArgumentError, "MCP root must be a directory" unless File.directory?(@root)
    end

    def server
      @server ||= build_server
    end

    def run
      MCP::Server::Transports::StdioTransport.new(server).open
    end

    private

    def build_server
      result = MCP::Server.new(name: "breadkit", version: VERSION,
                               instructions: "Read-only circuit tools. Files may be YAML, TOML, or JSON IR; in-memory drafts may be YAML or TOML. Ruby is never evaluated.")
      responder, resolver, nets, valid = method(:respond), method(:resolve), method(:inspect_nets), method(:valid_circuit)
      draft_resolver, draft_linter, draft_renderer = method(:resolve_draft), method(:lint_draft), method(:render_draft)
      path_schema = { type: "object", properties: { path: { type: "string", minLength: 1 } },
                      required: ["path"], additionalProperties: false }
      result.define_tool(name: "breadkit_resolve", description: "Resolve a circuit and report its parts, wiring, and diagnostics.",
                         input_schema: path_schema, annotations: read_only_annotations) do |path:|
        responder.call { resolver.call(path) }
      end
      result.define_tool(name: "breadkit_nets", description: "List the resolved electrical nets and potentials of a circuit.",
                         input_schema: { type: "object", properties: path_schema[:properties].merge(state: { type: "string" }),
                                         required: ["path"], additionalProperties: false }, annotations: read_only_annotations) do |path:, state: nil|
        responder.call { nets.call(path, state) }
      end
      result.define_tool(name: "breadkit_ir", description: "Export a valid circuit as Breadkit JSON IR.",
                         input_schema: path_schema, annotations: read_only_annotations) do |path:|
        responder.call { valid.call(path).to_ir }
      end
      source_schema = { type: "object", properties: { format: { type: "string", enum: %w[yaml toml] },
                                                      source: { type: "string", minLength: 1 } },
                        required: %w[format source], additionalProperties: false }
      result.define_tool(name: "breadkit_resolve_source", description: "Validate a YAML or TOML draft in memory and report diagnostics.",
                         input_schema: source_schema, annotations: read_only_annotations) do |format:, source:|
        responder.call { draft_resolver.call(format, source) }
      end
      result.define_tool(name: "breadkit_lint_source", description: "Lint a YAML or TOML draft in memory; requires breadkit-lint.",
                         input_schema: source_schema, annotations: read_only_annotations) do |format:, source:|
        responder.call { draft_linter.call(format, source) }
      end
      result.define_tool(name: "breadkit_render_source", description: "Render a valid YAML or TOML draft as static SVG; requires breadkit-render.",
                         input_schema: source_schema, annotations: read_only_annotations) do |format:, source:|
        responder.call { draft_renderer.call(format, source) }
      end
      result
    end

    def read_only_annotations
      { read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: false }
    end

    def respond
      value = yield
      json = JSON.generate(value)
      raise ArgumentError, "tool response exceeds 8 MiB" if json.bytesize > MAX_INPUT_BYTES

      MCP::Tool::Response.new([{ type: "text", text: json }], structured_content: value)
    rescue StandardError => e
      MCP::Tool::Response.new([{ type: "text", text: e.message }], error: true)
    end

    def resolve(path)
      circuit = load_circuit(path)
      summary(circuit)
    end

    def summary(circuit)
      { valid: circuit.diagnostics.none? { |item| item.severity == "error" }, title: circuit.title,
        boards: board_summary(circuit), components: circuit.components.keys, wires: circuit.wires.length,
        supplies: circuit.supplies.map(&:name), diagnostics: circuit.diagnostics.map { |item| diagnostic_data(item) } }
    end

    def resolve_draft(format, source)
      result = summary(load_draft(format, source))
      result[:diagnostics].each do |diagnostic|
        location = diagnostic[:location]
        location[:path] = "draft.bk.#{format == 'yaml' ? 'yml' : 'toml'}" if location && location[:path] == draft_path(format)
      end
      result
    end

    def lint_draft(format, source)
      circuit = load_draft(format, source)
      require_optional("breadkit/lint", "breadkit-lint")
      engine = Lint::Engine.new
      raise ArgumentError, "breadkit-lint with Engine#run_circuit is required" unless engine.respond_to?(:run_circuit)

      result = engine.run_circuit(circuit, path: draft_path(format))
      report = Lint::Formatter.new.json([result])
      raise ArgumentError, "lint report exceeds 8 MiB" if report.bytesize > MAX_INPUT_BYTES

      parsed = JSON.parse(report)
      parsed.fetch("files").each do |file|
        virtual_path = file.fetch("path")
        file["path"] = "draft.bk.#{format == 'yaml' ? 'yml' : 'toml'}"
        file.fetch("offenses").each do |offense|
          location = offense["location"]
          location["path"] = file["path"] if location && location["path"] == virtual_path
        end
      end
      parsed
    end

    def render_draft(format, source)
      circuit = load_draft(format, source)
      errors = circuit.diagnostics.select { |item| item.severity == "error" }
      raise DSLError, errors.map(&:message).join("; ") unless errors.empty?

      require_optional("breadkit/render", "breadkit-render")
      svg = Render::SvgRenderer.new.render(circuit, theme: "dark", interactive_layers: false)
      raise ArgumentError, "rendered SVG exceeds 8 MiB" if svg.bytesize > MAX_INPUT_BYTES

      { svg: svg }
    end

    def require_optional(path, gem_name)
      require path
    rescue LoadError => e
      raise ArgumentError, "#{gem_name} is required for this tool (#{e.message})"
    end

    def draft_path(format)
      raise ArgumentError, "format must be yaml or toml" unless %w[yaml toml].include?(format)

      File.join(@root, "_breadkit_mcp_draft.bk.#{format == 'yaml' ? 'yml' : 'toml'}")
    end

    def load_draft(format, source)
      unless source.is_a?(String) && source.encoding == Encoding::UTF_8 && source.valid_encoding? && !source.empty?
        raise ArgumentError, "source must be nonempty UTF-8 text"
      end
      raise ArgumentError, "input source exceeds 8 MiB" if source.bytesize > MAX_INPUT_BYTES

      document = StructuredInput.load_source(draft_path(format), source)
      (document.part_paths + document.board_paths).each { |dependency| checked_path(dependency) }
      Resolver.new.call(document)
    end

    def inspect_nets(path, state_name)
      circuit = valid_circuit(path)
      state = circuit.state(state_name) unless state_name == "base"
      { state: state_name || "base", nets: circuit.nets(state).map do |net|
        { name: net.name, members: net.members, holes: net.holes, potential: net.potential }
      end }
    end

    def valid_circuit(path)
      circuit = load_circuit(path)
      errors = circuit.diagnostics.select { |item| item.severity == "error" }
      raise DSLError, errors.map(&:message).join("; ") unless errors.empty?

      circuit
    end

    def load_circuit(path)
      file = circuit_path(path)
      return IR::Reader.new.read_file(file) if file.end_with?(".json")

      document = StructuredInput.load_file(file)
      (document.part_paths + document.board_paths).each { |dependency| checked_path(dependency) }
      PartLock.verify(document, file)
      Resolver.new.call(document)
    end

    def circuit_path(path)
      raise ArgumentError, "path must be text" unless path.is_a?(String) && !path.empty?
      raise ArgumentError, "MCP accepts only YAML, TOML, or JSON IR circuit files" unless EXTENSIONS.any? { |extension| path.end_with?(extension) }

      file = checked_path(path)
      unless EXTENSIONS.any? { |extension| file.end_with?(extension) }
        raise ArgumentError, "MCP accepts only YAML, TOML, or JSON IR circuit files"
      end
      file
    end

    def checked_path(path)
      expanded = File.expand_path(path, @root)
      raise ArgumentError, "path is outside the MCP root" unless inside_root?(expanded)

      real = File.realpath(expanded)
      raise ArgumentError, "path is outside the MCP root" unless inside_root?(real)
      raise ArgumentError, "path must be a file" unless File.file?(real)
      raise ArgumentError, "input file exceeds 8 MiB" if File.size(real) > MAX_INPUT_BYTES

      real
    end

    def inside_root?(path)
      prefix = @root == File::SEPARATOR ? @root : "#{@root}#{File::SEPARATOR}"
      path.start_with?(prefix)
    end

    def board_summary(circuit)
      if circuit.multi_board?
        circuit.boards.map { |name, board| { name: name, type: board.definition.id } }
      else
        [{ type: circuit.board.definition.id }]
      end
    end

    def diagnostic_data(item)
      location = item.location && { path: item.location.path, line: item.location.line }
      { code: item.code, severity: item.severity, message: item.message, targets: item.targets, location: location }
    end
  end
end
