# frozen_string_literal: true

require "stringio"
require "tmpdir"

RSpec.describe "CLI circuit diagnostics" do
  def run_captured(*args)
    old_out, old_err = $stdout, $stderr
    output, errors = StringIO.new, StringIO.new
    $stdout, $stderr = output, errors
    status = Breadkit::CLI.new.run(args)
    [status, output.string, errors.string]
  ensure
    $stdout, $stderr = old_out, old_err
  end

  it "reports invalid holes before nets or inspection output" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "invalid.bk.rb")
      File.write(path, 'board :half; resistor :R1, "330", pins: %w[a1 a3]; wire "T+999", "b3"')
      [%w[nets], %w[where a1], %w[explain R1], %w[bom]].each do |command|
        status, output, errors = run_captured(*command, path)
        expect(status).to eq(1)
        expect(output).to be_empty
        expect(errors).to include("invalid_hole", "T+999")
      end
    end
  end
end
