#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"

root = File.expand_path("..", __dir__)
files = Dir[File.join(root, "examples", "bad", "*.bk.rb")].sort
abort "no bad examples found" if files.empty?

failed = false
files.each do |path|
  expected = File.foreach(path).filter_map { |line| line[/\A#\s*expect:\s*(\S+)/, 1] }.first
  unless expected
    warn "#{path}: missing '# expect: Rule/Id' header"
    failed = true
    next
  end

  stdout, stderr, status = Open3.capture3("bklint", "--format", "json", path, chdir: root)
  report = JSON.parse(stdout)
  rules = report.fetch("files").flat_map { |file| file.fetch("offenses").map { |offense| offense.fetch("rule") } }
  unless status.exitstatus == 1 && rules.include?(expected)
    warn "#{path}: expected #{expected}, got exit #{status.exitstatus} and #{rules.inspect}"
    warn stderr unless stderr.empty?
    failed = true
    next
  end

  puts "#{File.basename(path)}: #{expected} detected"
rescue JSON::ParserError, KeyError => e
  warn "#{path}: invalid bklint JSON (#{e.message})"
  failed = true
end

exit(failed ? 1 : 0)
