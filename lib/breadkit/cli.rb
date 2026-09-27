# frozen_string_literal: true

require "optparse"

module Breadkit
  class CLI
    USAGE = <<~TEXT.freeze
      Usage: breadkit COMMAND [OPTIONS]
        ir [--force] [--timeout SECONDS] FILE
        nets [--state SWITCH] [--timeout SECONDS] FILE
        where HOLE FILE | explain PART FILE | bom FILE | diff OLD NEW
        suggest FILE (show free-hole wire candidates for unmet connection intent)
        kit --inventory KIT.yml FILE (allocate measured jumpers to straight board wires)
        export --format kicad|spice|wokwi|pins|fritzing FILE
        fmt FILE (declarative YAML or TOML; prints formatted source)
        lock FILE (pin local part and board definitions in breadkit.lock)
        parts [FILE] | parts show PART [FILE] | check-part YAML
        new [FILE] --template led|555|arduino | doctor | console FILE
        --version | --help
    TEXT
    TEMPLATES = %w[led 555 arduino].freeze

    def run(argv)
      args = argv.dup
      command = args.shift
      case command
      when "ir", "nets"
        state_name = nil
        force = false
        timeout = 10.0
        if command == "nets"
          OptionParser.new do |opts|
            opts.on("--state SWITCH") { |value| state_name = value }
            opts.on("--timeout SECONDS", Float) { |value| timeout = value }
          end.parse!(args)
        else
          OptionParser.new do |opts|
            opts.on("--force") { force = true }
            opts.on("--timeout SECONDS", Float) { |value| timeout = value }
          end.parse!(args)
        end
        path = args.shift
        raise ArgumentError, "usage: breadkit #{command} FILE" unless path
        raise ArgumentError, "unexpected arguments: #{args.join(' ')}" unless args.empty?

        circuit = Breadkit.load(path, timeout: timeout)
        if command == "ir"
          has_errors = report_errors(circuit)
          return 1 if has_errors && !force

          puts JSON.pretty_generate(circuit.to_ir)
          0
        else
          return 1 if report_errors(circuit)

          state = circuit.states.find { |item| item.name == state_name } if state_name
          raise ArgumentError, "unknown switch state #{state_name}" if state_name && !state
          circuit.nets(state).each { |net| puts "#{net.name}: #{net.members.join(', ')}" }
          0
        end
      when "parts"
        show = args.shift if args.first == "show"
        name = args.shift if show
        raise ArgumentError, "usage: breadkit parts show PART [FILE]" if show && !name
        path = args.shift
        unexpected!(args)
        document = DSL.load_file(path) if path
        library = PartLibrary.new(extra_paths: document&.part_paths || [], extra_definitions: document&.part_definitions || [])
        if show
          part = library.find(name)
          raise ArgumentError, "unknown part #{name}" unless part
          puts JSON.pretty_generate(part.data)
        else
          library.all.each { |part| puts "#{part.id}\t#{part.data['category']}" }
        end
        0
      when "check-part"
        path = required!(args, "check-part YAML")
        data = YAML.safe_load(File.read(path, encoding: "UTF-8"), aliases: false)
        raise ArgumentError, "part definition must be a YAML mapping" unless data.is_a?(Hash)
        part = PartLibrary.new(extra_paths: [path]).find(data["id"])
        raise ArgumentError, "part definition needs an id" unless part
        puts "Valid part: #{part.id} (#{part.pins.length} pins)"
        0
      when "where", "explain", "bom"
        state_name = nil
        timeout = 10.0
        OptionParser.new do |opts|
          opts.on("--state SWITCH") { |value| state_name = value }
          opts.on("--timeout SECONDS", Float) { |value| timeout = value }
        end.parse!(args)
        target = args.shift unless command == "bom"
        path = required!(args, command == "bom" ? "bom FILE" : "#{command} TARGET FILE")
        circuit = Breadkit.load(path, timeout: timeout)
        return 1 if report_errors(circuit)

        state = select_state(circuit, state_name)
        case command
        when "where" then show_where(circuit, target, state)
        when "explain" then show_explain(circuit, target, state)
        when "bom" then show_bom(circuit)
        end
        0
      when "new"
        template = nil
        OptionParser.new { |opts| opts.on("--template NAME") { |value| template = value } }.parse!(args)
        raise ArgumentError, "choose --template #{TEMPLATES.join('|')}" unless TEMPLATES.include?(template)
        path = args.shift || "#{template}.bk.rb"
        unexpected!(args)
        source = File.expand_path("templates/#{template}.bk.rb", __dir__)
        File.open(path, "wx:UTF-8") { |file| file.write(File.read(source, encoding: "UTF-8")) }
        puts "Created #{path}"
        0
      when "doctor"
        unexpected!(args)
        supported = Gem::Version.new(RUBY_VERSION) >= Gem::Version.new("3.3")
        puts "Ruby #{RUBY_VERSION}: #{supported ? 'supported' : 'requires 3.3 or newer'}"
        %w[bklint bkrender].each do |name|
          found = ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? { |dir| File.executable?(File.join(dir, name)) }
          puts "#{name}: #{found ? 'available' : 'not installed'}"
        end
        supported ? 0 : 1
      when "diff"
        old_path = args.shift
        new_path = required!(args, "diff OLD NEW")
        raise ArgumentError, "usage: breadkit diff OLD NEW" unless old_path
        show_diff(Breadkit.load(old_path), Breadkit.load(new_path))
        0
      when "export"
        format = nil
        OptionParser.new { |opts| opts.on("--format NAME") { |value| format = value } }.parse!(args)
        raise ArgumentError, "choose --format #{Exporters::FORMATS.join('|')}" unless Exporters::FORMATS.include?(format)
        path = required!(args, "export --format FORMAT FILE")
        puts Exporters.call(Breadkit.load(path), format: format)
        0
      when "fmt"
        path = required!(args, "fmt FILE")
        print Formatter.call(path)
        0
      when "lock"
        path = required!(args, "lock FILE")
        puts "Wrote #{PartLock.write(path)}"
        0
      when "suggest"
        path = required!(args, "suggest FILE")
        circuit = Breadkit.load(path)
        return 1 if report_errors(circuit)

        puts JSON.pretty_generate(circuit.wire_suggestions)
        0
      when "kit"
        inventory = nil
        OptionParser.new { |opts| opts.on("--inventory FILE") { |value| inventory = value } }.parse!(args)
        raise ArgumentError, "usage: breadkit kit --inventory KIT.yml FILE" unless inventory

        path = required!(args, "kit --inventory KIT.yml FILE")
        circuit = Breadkit.load(path)
        return 1 if report_errors(circuit)

        puts JSON.pretty_generate(JumperKit.load(inventory).allocate(circuit))
        0
      when "console"
        path = required!(args, "console FILE")
        circuit = Breadkit.load(path)
        puts "Circuit loaded as `circuit`. Try circuit.nets or circuit.components."
        require "irb"
        binding.irb(show_code: false) # rubocop:disable Lint/Debugger -- This command intentionally opens a REPL.
        0
      when "--version", "-v"
        raise ArgumentError, "unexpected arguments: #{args.join(' ')}" unless args.empty?

        puts Breadkit::VERSION
        0
      when "-h", "--help", "help"
        puts USAGE
        0
      else
        warn USAGE
        2
      end
    rescue StandardError => e
      warn "breadkit: #{e.message}"
      2
    end

    private

    def report_errors(circuit)
      errors = circuit.diagnostics.select { |item| item.severity == "error" }
      errors.each { |item| warn "breadkit: #{item.code}: #{item.message}" }
      !errors.empty?
    end

    def required!(args, usage)
      path = args.shift
      raise ArgumentError, "usage: breadkit #{usage}" unless path
      unexpected!(args)
      path
    end

    def unexpected!(args)
      raise ArgumentError, "unexpected arguments: #{args.join(' ')}" unless args.empty?
    end

    def select_state(circuit, name)
      return unless name
      circuit.states.find { |item| item.name == name } || raise(ArgumentError, "unknown switch state #{name}")
    end

    def show_where(circuit, reference, state)
      hole = circuit.board.hole(reference)
      raise ArgumentError, "unknown hole #{reference}" unless hole
      strip = circuit.board.strip(hole.id)
      pins = circuit.components.values.flat_map do |component|
        component.pins.values.filter_map do |pin|
          "#{component.ref}.#{pin.name}@#{pin.hole_id}" if strip.include?(pin.hole_id)
        end
      end
      wires = circuit.wires.flat_map do |wire|
        [wire.from, wire.to].filter_map { |end_at| "#{wire.id}@#{end_at}" if strip.include?(end_at) }
      end
      net = circuit.net_of(hole.id, state)
      puts "Hole: #{hole.id}"
      puts "Strip: #{strip.join(', ')}"
      puts "Net: #{net&.name || 'unconnected'}"
      puts "Pins: #{pins.empty? ? 'none' : pins.join(', ')}"
      puts "Wires: #{wires.empty? ? 'none' : wires.join(', ')}"
    end

    def show_explain(circuit, reference, state)
      component = circuit.components[reference]
      raise ArgumentError, "unknown component #{reference}" unless component
      puts "#{component.ref}: #{component.part.id}#{" #{component.value}" if component.value}"
      dc = circuit.dc_analysis(state)
      potentials = []
      component.pins.each_value do |pin|
        net = circuit.net_of("#{component.ref}.#{pin.name}", state)
        potential = dc.success? && net && dc.voltages.key?(net.name) ? dc.voltages[net.name] : net&.potential
        potentials << potential
        voltage = potential.nil? ? "unknown" : "#{format('%.3g', potential)} V"
        voltage += " (relative)" if dc.success? && net && dc.floating.any? { |group| group.include?(net.name) }
        puts "  #{pin.name}: #{pin.hole_id || 'offboard'} | #{net&.name || 'unconnected'} | #{voltage}"
      end
      current = dc.currents[component.ref]&.abs if dc.success?
      current ||= if component.part.id == "resistor" && potentials.length == 2 && potentials.none?(&:nil?)
        resistance = Value.parse(component.value)
        (potentials[0] - potentials[1]).abs / resistance if resistance.positive?
      end
      puts "Current: #{current ? "#{format('%.3g', current)} A" : 'unknown (DC operating point unavailable)'}"
      puts "Power: #{format('%.3g', dc.power[component.ref])} W" if dc.success? && dc.power.key?(component.ref)
      dc.assumptions.each { |assumption| puts "Assumption: #{assumption}" } if dc.success? && dc.currents.key?(component.ref)
    end

    def show_bom(circuit)
      counts = circuit.components.values.map { |component| [component.part.id, component.value&.to_s] }.tally
      puts "Count\tPart\tValue"
      counts.sort_by { |(part, value), _count| [part, value.to_s] }.each do |(part, value), count|
        puts "#{count}\t#{part}\t#{value}"
      end
      puts "#{circuit.wires.length}\tjumper_wire\t"
    end

    def show_diff(old_circuit, new_circuit)
      old_circuit.diff(new_circuit).each do |key, (before, after)|
        puts "- #{key}: #{before}" if before
        puts "+ #{key}: #{after}" if after
      end
    end
  end
end
