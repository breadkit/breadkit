# frozen_string_literal: true

require_relative "lib/breadkit/version"

Gem::Specification.new do |spec|
  spec.name = "breadkit"
  spec.version = Breadkit::VERSION
  spec.authors = ["Yudai Takada"]
  spec.email = ["t.yudai92@gmail.com"]

  spec.summary = "Describe and analyze breadboard circuits with a Ruby DSL."
  spec.description = "Breadkit resolves breadboard wiring DSL files into deterministic circuit connectivity and JSON IR."
  spec.homepage = "https://github.com/breadkit/breadkit"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "#{spec.homepage}/tree/main"
  spec.metadata["bug_tracker_uri"] = "#{spec.homepage}/issues"
  spec.metadata["documentation_uri"] = "#{spec.homepage}/tree/main/docs"
  spec.metadata["rubygems_mfa_required"] = "true"

  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) || f.start_with?(*%w[bin/ Gemfile .gitignore .rspec .rubocop.yml Rakefile spec/ .github/ examples/ scripts/ .idea/ docs/rules/]) ||
      %w[CHANGELOG.md VERSION docs/DESIGN.md docs/WORK_PROCEDURE.md].include?(f)
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

end
