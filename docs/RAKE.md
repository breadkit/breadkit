# Check circuits with Rake

Install Rake for your project and add an opt-in task to its `Rakefile`:

```ruby
require "breadkit/rake_task"

Breadkit::RakeTask.new(:circuits, files: Dir["circuits/*.{bk.yml,bk.toml}"])
task default: :circuits
```

Run `bundle exec rake circuits`. The task loads each listed file, verifies
`breadkit.lock` when present, and fails on core resolution errors. It reports
the first failing file and its diagnostics. The task does not run lint rules;
run `bklint` separately when you need electrical and layout checks.

Only files passed in `files:` are loaded. Ruby `.bk.rb` circuits execute Ruby
code, so include them only when you trust their contents. YAML and TOML
circuit files are parsed as data.
