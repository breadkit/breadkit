# frozen_string_literal: true

require "optparse"

module Breadkit
  class CLI
    def run(argv)
      command = argv.shift
      case command
      when "ir", "nets"
        path = argv.shift
        raise ArgumentError, "usage: breadkit #{command} FILE" unless path
        state_name = nil
        if command == "nets"
          OptionParser.new { |opts| opts.on("--state SWITCH") { |value| state_name = value } }.parse!(argv)
          raise ArgumentError, "unexpected arguments: #{argv.join(' ')}" unless argv.empty?
        end
        circuit = Breadkit.load(path)
        if command == "ir"
          puts JSON.pretty_generate(circuit.to_ir)
        else
          state = circuit.states.find { |item| item.name == state_name } if state_name
          raise ArgumentError, "unknown switch state #{state_name}" if state_name && !state
          circuit.nets(state).each { |net| puts "#{net.name}: #{net.members.join(', ')}" }
        end
        circuit.diagnostics.empty? ? 0 : 1
      when "parts"
        PartLibrary.new.all.each { |part| puts "#{part.id}\t#{part.data['category']}" }
        0
      else
        puts "Usage: breadkit ir FILE | nets FILE | parts"
        command.nil? || %w[-h --help help].include?(command) ? 0 : 2
      end
    rescue StandardError => e
      warn "breadkit: #{e.message}"
      2
    end
  end
end
