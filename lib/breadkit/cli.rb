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
        circuit = Breadkit.load(path)
        if command == "ir"
          puts JSON.pretty_generate(circuit.to_ir)
        else
          circuit.nets.each { |net| puts "#{net.name}: #{net.members.join(', ')}" }
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
