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
                               instructions: "Read-only circuit tools. Inputs must be declarative YAML, TOML, or JSON IR files inside the configured root.")
      responder, resolver, nets, valid = method(:respond), method(:resolve), method(:inspect_nets), method(:valid_circuit)
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
      result
    end

    def read_only_annotations
      { read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: false }
    end

    def respond
      value = yield
      MCP::Tool::Response.new([{ type: "text", text: JSON.generate(value) }], structured_content: value)
    rescue StandardError => e
      MCP::Tool::Response.new([{ type: "text", text: e.message }], error: true)
    end

    def resolve(path)
      circuit = load_circuit(path)
      { valid: circuit.diagnostics.none? { |item| item.severity == "error" }, title: circuit.title,
        boards: board_summary(circuit), components: circuit.components.keys, wires: circuit.wires.length,
        supplies: circuit.supplies.map(&:name), diagnostics: circuit.diagnostics.map { |item| diagnostic_data(item) } }
    end

    def inspect_nets(path, state_name)
      circuit = valid_circuit(path)
      state = nil
      if state_name && state_name != "base"
        names = state_name.split(",", -1)
        switches = names.map { |name| circuit.components[name] }
        if names.uniq.length != names.length || switches.any? { |item| !item || Array(item.part.data["switch"]).empty? }
          raise ArgumentError, "unknown switch state #{state_name}"
        end

        closed = switches.flat_map { |component| Array(component.part.data["switch"]).map { |pair| [component, pair] } }
        state = State.new(name: state_name, closed_switches: closed)
      end
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
