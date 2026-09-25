# frozen_string_literal: true

require "bundler"
require "rake"

GEMS = %w[breadkit breadkit-render breadkit-lint].freeze

def each_gem(task)
  bundle_path = ENV["BUNDLE_PATH"]
  GEMS.each do |name|
    Dir.chdir(name) do
      Bundler.with_unbundled_env do
        sh({ "BUNDLE_PATH" => bundle_path }.compact, "bundle", "exec", "rake", task)
      end
    end
  end
end

def version_constraint(version)
  major, minor = version.split(".")
  major == "0" ? "~> 0.#{minor}.0" : "~> #{major}.#{minor}"
end

desc "Run RuboCop and RSpec in all gems"
task :test => %i[rubocop spec]
task :default => :test

desc "Run RSpec in all gems"
task(:spec) { each_gem("spec") }

desc "Run RuboCop in all gems"
task(:rubocop) { each_gem("rubocop") }

desc "Verify the lockstep version and core dependency constraints"
task :check_versions do
  version = File.read("VERSION").strip
  files = Dir["*/lib/**/version.rb"]
  abort "expected three gem version files, found #{files.length}" unless files.length == GEMS.length

  versions = files.to_h do |path|
    value = File.read(path)[/VERSION\s*=\s*"([^"]+)"/, 1]
    abort "missing VERSION constant in #{path}" unless value
    [path, value]
  end
  abort "gem versions do not match VERSION=#{version}: #{versions}" unless versions.values.uniq == [version]

  dependency = version_constraint(version)
  %w[breadkit-render breadkit-lint].each do |name|
    gemspec = File.read("#{name}/#{name}.gemspec")
    actual = gemspec[/add_dependency\s+"breadkit",\s*"([^"]+)"/, 1]
    abort "#{name} depends on breadkit #{actual.inspect}, expected #{dependency}" unless actual == dependency
  end
end

desc "Build all gems into their pkg directories"
task :build => :check_versions do
  each_gem("build")
end

desc "Update the shared version and inter-gem dependency ranges"
task :bump, [:version] do |_task, args|
  version = args[:version].to_s
  abort "usage: rake 'bump[MAJOR.MINOR.PATCH]'" unless /\A(?:0|[1-9]\d*)\.\d+\.\d+\z/.match?(version)

  constraint = version_constraint(version)
  replacements = { "VERSION" => "#{version}\n" }
  Dir["*/lib/**/version.rb"].each do |path|
    source = File.read(path)
    updated = source.sub(/VERSION\s*=\s*"[^"]+"/) { %(VERSION = "#{version}") }
    abort "missing VERSION constant in #{path}" if updated == source
    replacements[path] = updated
  end

  %w[breadkit-render breadkit-lint].each do |name|
    path = "#{name}/#{name}.gemspec"
    source = File.read(path)
    updated = source.sub(/add_dependency\s+"breadkit",\s*"[^"]+"/) do
      %(add_dependency "breadkit", "#{constraint}")
    end
    abort "missing breadkit dependency in #{path}" if updated == source
    replacements[path] = updated
  end

  replacements.each { |path, content| File.write(path, content) }
  puts "bumped to #{version} (breadkit #{constraint})"
end
