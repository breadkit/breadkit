# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "rubocop/rake_task"

RSpec::Core::RakeTask.new(:spec) { |task| task.rspec_opts = "-Ilib -I../breadkit/lib" }
RuboCop::RakeTask.new { |task| task.options = ["--cache", "false"] }

task default: %i[rubocop spec]
