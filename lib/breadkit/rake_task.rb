# frozen_string_literal: true

require_relative "../breadkit"
require "rake"

module Breadkit
  class RakeTask
    attr_reader :task

    def initialize(name = :breadkit, files:)
      raise ArgumentError, "RakeTask needs a task name" if name.to_s.empty?
      raise ArgumentError, "RakeTask files must be a nonempty list of paths" unless files.is_a?(Array) && !files.empty? && files.all? { |path| path.is_a?(String) && !path.empty? }

      @task = Rake::Task.define_task(name) do
        files.each do |path|
          circuit = Breadkit.load(path)
          errors = circuit.diagnostics.select { |item| item.severity == "error" }
          raise "#{path}: #{errors.map { |item| "#{item.code}: #{item.message}" }.join('; ')}" unless errors.empty?

          puts "Checked #{path}"
        end
      end
    end
  end
end
