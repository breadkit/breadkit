# frozen_string_literal: true

module SnapshotHelpers
  def expect_svg_snapshot(name, svg)
    path = File.expand_path("../snapshots/#{name}.svg", __dir__)
    if ENV["UPDATE_SNAPSHOTS"] == "1"
      File.write(path, svg)
    else
      expect(File.file?(path)).to be(true), "missing #{path}; run with UPDATE_SNAPSHOTS=1 to create it"
      expect(svg).to eq(File.read(path)), "snapshot mismatch: #{name}"
    end
  end
end

RSpec.configure { |config| config.include SnapshotHelpers }
