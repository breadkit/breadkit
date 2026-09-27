# frozen_string_literal: true

require "rake"
require "tmpdir"
require "breadkit/rake_task"

RSpec.describe Breadkit::RakeTask do
  around do |example|
    previous = Rake.application
    Rake.application = Rake::Application.new
    example.run
  ensure
    Rake.application = previous
  end

  it "registers a task that checks explicit circuit files" do
    Dir.mktmpdir do |dir|
      file = File.join(dir, "good.bk.yml")
      File.write(file, "board: mini\nwires:\n  - {from: a1, to: a2}\n")
      described_class.new(:circuits, files: [file])
      expect { Rake::Task[:circuits].invoke }.to output(/Checked .*good\.bk\.yml/).to_stdout
    end
  end

  it "fails the task with a resolver diagnostic and rejects an empty file list" do
    Dir.mktmpdir do |dir|
      file = File.join(dir, "bad.bk.yml")
      File.write(file, "board: mini\nwires:\n  - {from: z99, to: a1}\n")
      described_class.new(:circuits, files: [file])
      expect { Rake::Task[:circuits].invoke }.to raise_error(RuntimeError, /invalid_hole/)
    end
    expect { described_class.new(:empty, files: []) }.to raise_error(ArgumentError, /files/)
  end
end
