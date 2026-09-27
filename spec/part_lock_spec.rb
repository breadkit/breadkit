# frozen_string_literal: true

require "digest"
require "stringio"
require "tmpdir"

RSpec.describe "local definition lock" do
  def setup_project(dir)
    parts = File.join(dir, "parts")
    Dir.mkdir(parts)
    definition = File.join(parts, "sensor.yml")
    File.write(definition, "id: sensor\nplacement: offboard\npins:\n  - {num: 1, name: SIG}\n")
    circuit = File.join(dir, "logger.bk.yml")
    File.write(circuit, "board: mini\nuse_parts: [parts/*.yml]\noffboard:\n  - {ref: S1, type: sensor}\n")
    [circuit, definition]
  end

  it "writes relative SHA-256 entries and rejects changed or newly matched parts" do
    Dir.mktmpdir do |dir|
      circuit, definition = setup_project(dir)
      path = Breadkit::PartLock.write(circuit)
      lock = JSON.parse(File.read(path))
      record = lock.fetch("circuits").fetch("logger.bk.yml")
      expect(record.fetch("breadkit")).to eq(Breadkit::VERSION)
      expect(record.fetch("parts")).to eq([{ "path" => "parts/sensor.yml", "sha256" => Digest::SHA256.file(definition).hexdigest }])
      expect(Breadkit.load(circuit).components).to have_key("S1")

      File.write(definition, File.read(definition).sub("SIG", "DATA"))
      expect { Breadkit.load(circuit) }.to raise_error(Breadkit::DSLError, /checksum.*parts\/sensor.yml/)
      Breadkit::PartLock.write(circuit)
      expect(Breadkit.load(circuit).components).to have_key("S1")

      File.write(File.join(dir, "parts", "extra.yml"), "id: extra\nplacement: offboard\npins:\n  - {num: 1}\n")
      expect { Breadkit.load(circuit) }.to raise_error(Breadkit::DSLError, /definition set changed/)
    end
  end

  it "pins custom board definitions and keeps separate circuit entries" do
    Dir.mktmpdir do |dir|
      circuit, = setup_project(dir)
      board = File.join(dir, "custom.yml")
      File.write(board, "id: custom\nterminal:\n  columns: 2\n  rows: [a, b]\n  groups: [[a, b]]\n")
      second = File.join(dir, "board.bk.yml")
      File.write(second, "use_boards: [custom.yml]\nboard: custom\n")
      Breadkit::PartLock.write(circuit)
      Breadkit::PartLock.write(second)
      entries = JSON.parse(File.read(File.join(dir, "breadkit.lock"))).fetch("circuits")
      expect(entries.keys).to contain_exactly("board.bk.yml", "logger.bk.yml")
      expect(entries.fetch("board.bk.yml").fetch("boards").first.fetch("path")).to eq("custom.yml")
      expect(Breadkit.load(second).board.definition.id).to eq("custom")
      File.write(board, File.read(board).sub("columns: 2", "columns: 3"))
      expect { Breadkit.load(second) }.to raise_error(Breadkit::DSLError, /checksum.*custom.yml/)
      expect(Breadkit.load(circuit).components).to have_key("S1")
    end
  end

  it "rejects missing entries and mismatched core versions without evaluating lock contents" do
    Dir.mktmpdir do |dir|
      circuit, = setup_project(dir)
      lock_path = Breadkit::PartLock.write(circuit)
      another = File.join(dir, "other.bk.yml")
      File.write(another, "board: mini\n")
      expect { Breadkit.load(another) }.to raise_error(Breadkit::DSLError, /no entry/)
      data = JSON.parse(File.read(lock_path))
      data.fetch("circuits").fetch("logger.bk.yml")["breadkit"] = "0.0.0"
      File.write(lock_path, JSON.pretty_generate(data))
      expect { Breadkit.load(circuit) }.to raise_error(Breadkit::DSLError, /version mismatch/)
      File.write(lock_path, "not JSON")
      expect { Breadkit.load(circuit) }.to raise_error(Breadkit::DSLError, /invalid breadkit.lock/)
    end
  end

  it "exposes lock generation through the CLI" do
    Dir.mktmpdir do |dir|
      circuit, = setup_project(dir)
      output = StringIO.new
      original = $stdout
      $stdout = output
      expect(Breadkit::CLI.new.run(["lock", circuit])).to eq(0)
      expect(output.string).to include("breadkit.lock")
      expect(Breadkit.load(circuit).components).to have_key("S1")
    ensure
      $stdout = original
    end
  end
end
