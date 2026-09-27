# frozen_string_literal: true

require "json_schemer"

RSpec.describe "standard part catalog" do
  let(:library) { Breadkit::PartLibrary.new }

  it "keeps every built-in definition within the public schema" do
    schema = JSONSchemer.schema(JSON.parse(File.read(File.expand_path("../schema/part-v1.json", __dir__))))
    Dir[File.expand_path("../data/parts/*.yml", __dir__)].each do |path|
      expect(schema.valid?(YAML.safe_load(File.read(path, encoding: "UTF-8"), aliases: false))).to be(true), path
    end
  end

  it "loads the expanded catalog with datasheet pin numbers" do
    expected = {
      "2n3904" => { 1 => "emitter", 2 => "base", 3 => "collector" },
      "2n3906" => { 1 => "emitter", 2 => "base", 3 => "collector" },
      "2n7000_onsemi_to92" => { 1 => "source", 2 => "gate", 3 => "drain" },
      "74hc00" => { 1 => "1A", 3 => "1Y", 8 => "3Y" },
      "74hc04" => { 1 => "1A", 2 => "1Y", 8 => "4Y" },
      "74hc08" => { 1 => "1A", 3 => "1Y", 8 => "3Y" },
      "74hc14" => { 1 => "1A", 2 => "1Y", 8 => "4Y" },
      "74hc165" => { 1 => "SH_LD", 9 => "QH", 16 => "VCC" },
      "74hc32" => { 1 => "1A", 3 => "1Y", 8 => "3Y" },
      "74hc595" => { 9 => "QH_SERIAL", 14 => "SER", 15 => "QA" },
      "cd4017" => { 1 => "Q5", 3 => "Q0", 12 => "CARRY" },
      "irlz44n" => { 1 => "gate", 2 => "drain", 3 => "source" },
      "l293d" => { 8 => "VCC2", 16 => "VCC1" },
      "lm358" => { 4 => "V_MINUS", 8 => "V_PLUS" },
      "lm393" => { 1 => "OUT1", 4 => "GND", 8 => "VCC" },
      "uln2003a" => { 8 => "E", 9 => "COM", 16 => "1C" },
      "ua7805" => { 1 => "INPUT", 2 => "GND", 3 => "OUTPUT" },
      "attiny85" => { 1 => "PB5_RESET", 8 => "VCC" },
      "atmega328p" => { 1 => "PC6_RESET", 20 => "AVCC", 28 => "PC5" },
      "pico" => { 1 => "GP0", 36 => "3V3_OUT", 40 => "VBUS" },
      "arduino_nano" => { 1 => "D13", 16 => "D1", 30 => "D12" },
      "sparkfun_pro_micro_5v" => { 1 => "D1", 12 => "D9", 24 => "RAW" },
      "seeed_xiao_samd21" => { 1 => "D0", 7 => "D6", 14 => "5V" },
      "esp32_devkitc_v4_wroom32e" => { 1 => "3V3", 19 => "5V", 20 => "FLASH_CLK" },
      "sc56_11ewa" => { 3 => "CATHODE1", 8 => "CATHODE2" },
      "wp154a4sureqbfzgc" => { 1 => "RED", 2 => "CATHODE", 3 => "BLUE", 4 => "GREEN" }
    }
    expected.each do |id, pins|
      part = library.find(id)
      expect(part).not_to be_nil
      pins.each { |number, name| expect(part.pin(number).fetch("name")).to eq(name) }
    end
  end

  it "places each supported board across the breadboard gap" do
    {
      "pico" => ["a1", "f1"],
      "arduino_nano" => ["b1", "f1"],
      "sparkfun_pro_micro_5v" => ["b1", "f1"],
      "seeed_xiao_samd21" => ["b1", "f1"],
      "esp32_devkitc_v4_wroom32e" => ["a1", "i1"],
      "sc56_11ewa" => ["b1", "f1"]
    }.each do |id, (anchor, opposite)|
      builder = Breadkit::DSL::Builder.new
      builder.instance_eval("board :full; part :U1, #{id.inspect}, at: #{anchor.inspect}", "parts.bk.rb", 1)
      circuit = Breadkit::Resolver.new.call(builder.document)
      expect(circuit.diagnostics.select { |item| item.severity == "error" }).to be_empty
      expect(circuit.components.fetch("U1").pins.values.first.hole_id).to eq(anchor)
      expect(circuit.components.fetch("U1").pins.values.last.hole_id).to eq(opposite)
    end
  end
end
