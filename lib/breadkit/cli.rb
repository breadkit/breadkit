# frozen_string_literal: true

require "optparse"

module Breadkit
  class CLI
    USAGE = "Usage: breadkit ir FILE | nets [--state SWITCH] FILE | parts [FILE] | --version".freeze

    def run(argv)
      args = argv.dup
      command = args.shift
      case command
      when "ir", "nets"
        state_name = nil
        if command == "nets"
          OptionParser.new { |opts| opts.on("--state SWITCH") { |value| state_name = value } }.parse!(args)
        end
        path = args.shift
        raise ArgumentError, "usage: breadkit #{command} FILE" unless path
        raise ArgumentError, "unexpected arguments: #{args.join(' ')}" unless args.empty?

        circuit = Breadkit.load(path)
        if command == "ir"
          errors = circuit.diagnostics.select { |item| item.severity == "error" }
          errors.each { |item| warn "breadkit: #{item.code}: #{item.message}" }
          return 1 unless errors.empty?

          puts JSON.pretty_generate(circuit.to_ir)
          0
        else
          state = circuit.states.find { |item| item.name == state_name } if state_name
          raise ArgumentError, "unknown switch state #{state_name}" if state_name && !state
          circuit.nets(state).each { |net| puts "#{net.name}: #{net.members.join(', ')}" }
          circuit.diagnostics.any? { |item| item.severity == "error" } ? 1 : 0
        end
      when "parts"
        path = args.shift
        raise ArgumentError, "unexpected arguments: #{args.join(' ')}" unless args.empty?

        document = DSL.load_file(path) if path
        PartLibrary.new(extra_paths: document&.part_paths || [], extra_definitions: document&.part_definitions || [])
                   .all.each { |part| puts "#{part.id}\t#{part.data['category']}" }
        0
      when "--version", "-v"
        raise ArgumentError, "unexpected arguments: #{args.join(' ')}" unless args.empty?

        puts Breadkit::VERSION
        0
      when "-h", "--help", "help"
        puts USAGE
        0
      else
        warn USAGE
        2
      end
    rescue StandardError => e
      warn "breadkit: #{e.message}"
      2
    end
  end
end
