# frozen_string_literal: true

require "breadkit"
require "json"
require "yaml"
require "optparse"
require "pathname"
require_relative "lint/version"

module Breadkit
  module Lint
    class Error < StandardError; end

    Offense = Struct.new(:rule, :severity, :message, :location, :targets, :state, keyword_init: true)

    class Rule
      attr_reader :id, :severity, :description, :state_sensitive, :checker

      def initialize(config = nil, id: nil, severity: nil, description: nil, state_sensitive: false, checker: nil)
        @config, @id, @severity, @description = config, id || self.class.id, severity || self.class.severity, description || self.class.description
        @state_sensitive, @checker = id ? state_sensitive : self.class.state_sensitive, checker
      end

      def self.rule(id, severity:, description:, state_sensitive: false)
        @id, @severity, @description, @state_sensitive = id, severity.to_s, description, state_sensitive
        Registry.register(self)
      end

      def self.id
        @id
      end

      def self.severity
        @severity
      end

      def self.description
        @description
      end

      def self.state_sensitive
        @state_sensitive
      end

      def check(_context)
        raise NotImplementedError
      end

      private

      def add_offense(context, message, location:, targets: {})
        context.offenses << Offense.new(rule: self.class.id, severity: context.config.severity(self.class), message: message,
                                        location: location, targets: targets, state: context.state.name)
      end
    end

    class Context
      attr_reader :circuit, :state, :config, :offenses

      def initialize(circuit, state, config)
        @circuit, @state, @config, @offenses = circuit, state, config, []
      end
    end

    class Registry
      RULES = [
        Rule.new(id: "Layout/InvalidHole", severity: "error", description: "Unknown board hole", checker: :diagnostic),
        Rule.new(id: "Layout/UnknownPart", severity: "error", description: "Unknown part definition", checker: :diagnostic),
        Rule.new(id: "Layout/UnknownPin", severity: "error", description: "Unknown pin reference", checker: :diagnostic),
        Rule.new(id: "Layout/DuplicateRef", severity: "error", description: "Duplicate component or wire reference", checker: :diagnostic),
        Rule.new(id: "Layout/InvalidPlacement", severity: "error", description: "Invalid component placement", checker: :diagnostic),
        Rule.new(id: "Layout/HoleConflict", severity: "error", description: "Multiple leads occupy one hole", checker: :diagnostic),
        Rule.new(id: "Layout/NoFreeHole", severity: "error", description: "No free hole is available", checker: :diagnostic),
        Rule.new(id: "Layout/PinsInSameStrip", severity: "error", description: "Two component pins share one conductive strip", checker: :same_strip),
        Rule.new(id: "Electrical/ShortCircuit", severity: "error", description: "Power constraints conflict", state_sensitive: true, checker: :short_circuit),
        Rule.new(id: "Electrical/ShortedComponent", severity: "warning", description: "A two-pin part is bypassed", checker: :shorted_component),
        Rule.new(id: "Electrical/FloatingPin", severity: "warning", description: "A component pin has no external connection", checker: :floating_pin),
        Rule.new(id: "Electrical/DanglingWire", severity: "warning", description: "A wire end has no other connection", checker: :dangling_wire),
        Rule.new(id: "Electrical/SplitRail", severity: "warning", description: "A used split rail segment has no supply", checker: :split_rail),
        Rule.new(id: "Electrical/MissingSeriesResistor", severity: "error", description: "An LED has an unprotected path across a supply", state_sensitive: true, checker: :missing_series_resistor),
        Rule.new(id: "Electrical/ReversePolarity", severity: "error", description: "A polarized part is connected backwards", state_sensitive: true, checker: :reverse_polarity),
        Rule.new(id: "Electrical/PowerPinUnconnected", severity: "warning", description: "An IC power or ground pin is not connected to a supply", checker: :power_pin),
        Rule.new(id: "Electrical/SupplyVoltageRange", severity: "error", description: "An IC supply voltage is outside its rated range", checker: :supply_range),
        Rule.new(id: "Electrical/NoCommonGround", severity: "warning", description: "Power supplies do not share a ground", checker: :common_ground),
        Rule.new(id: "Electrical/NetLabelConflict", severity: "error", description: "Different labels name one net", checker: :label_conflict),
        Rule.new(id: "Intent/ConnectionMismatch", severity: "error", description: "Wiring differs from declared expectations", checker: :expectations),
        Rule.new(id: "Intent/UnknownNet", severity: "error", description: "An expectation refers to an unknown net", checker: :expectations),
        Rule.new(id: "Style/WireColor", severity: "info", description: "A wire color differs from the supply color convention", checker: :wire_color)
      ].each(&:freeze).freeze

      @rules = RULES.dup

      def self.all
        @rules
      end

      def self.register(rule)
        raise Error, "duplicate rule #{rule.id}" if @rules.any? { |item| item.id == rule.id }
        @rules << rule
      end
    end

    class Config
      DEFAULT_PATH = File.expand_path("../../config/default.yml", __dir__)

      attr_reader :data

      def initialize(path = nil)
        @data = YAML.safe_load(File.read(DEFAULT_PATH), aliases: false) || {}
        @config_dir = path ? File.dirname(File.expand_path(path)) : Dir.pwd
        raise Error, "config not found: #{path}" if path && !File.file?(path)
        merge_file(path) if path
        Array(data["require"]).each { |file| require File.expand_path(file, @config_dir) }
        validate!
      end

      def severity(rule)
        value = data.dig(rule.id, "Severity") || rule.severity
        value.to_s.downcase
      end

      def enabled?(rule)
        enabled = data.dig(rule.id, "Enabled")
        enabled != false && enabled.to_s != "pending"
      end

      def switch_states
        data.dig("AllRules", "SwitchStates") || "single"
      end

      def fail_level
        data.dig("AllRules", "FailLevel") || "warning"
      end

      def excludes
        Array(data.dig("AllRules", "Exclude"))
      end

      def extra_parts
        Array(data["use_parts"]).flat_map { |pattern| Dir.glob(File.expand_path(pattern, @config_dir)) }
      end

      def unknown_rules
        reserved = %w[AllRules inherit_from require use_parts]
        (data.keys - reserved - Registry.all.map(&:id))
      end

      def excluded?(path)
        absolute = File.expand_path(path)
        relative = Pathname.new(absolute).relative_path_from(Pathname.new(@config_dir)).to_s
        excludes.any? do |pattern|
          File.fnmatch?(pattern, relative, File::FNM_PATHNAME | File::FNM_EXTGLOB) ||
            File.fnmatch?(pattern, absolute, File::FNM_PATHNAME | File::FNM_EXTGLOB)
        end
      end

      private

      def merge_file(path)
        @data = deep_merge(@data, load_config(path, []))
      rescue Psych::Exception => e
        raise Error, "invalid config #{path}: #{e.message}"
      end

      def load_config(path, stack)
        absolute = File.expand_path(path)
        raise Error, "cyclic config inheritance: #{(stack + [absolute]).join(' -> ')}" if stack.include?(absolute)
        override = YAML.safe_load(File.read(absolute), aliases: false) || {}
        parents = Array(override.delete("inherit_from")).reduce({}) do |merged, parent|
          parent_path = File.expand_path(parent, File.dirname(absolute))
          deep_merge(merged, load_config(parent_path, stack + [absolute]))
        end
        deep_merge(parents, override)
      end

      def deep_merge(left, right)
        left.merge(right) do |_key, current, replacement|
          current.is_a?(Hash) && replacement.is_a?(Hash) ? deep_merge(current, replacement) : replacement
        end
      end

      def validate!
        fail_level = data.dig("AllRules", "FailLevel")
        switch_states = data.dig("AllRules", "SwitchStates")
        raise Error, "invalid fail level: #{fail_level}" if fail_level && !%w[error warning info].include?(fail_level.to_s)
        raise Error, "invalid switch state mode: #{switch_states}" if switch_states && !%w[none single all].include?(switch_states.to_s)
        Registry.all.each do |rule|
          severity_value = data.dig(rule.id, "Severity")
          next unless severity_value && !%w[error warning info].include?(severity_value.to_s.downcase)
          raise Error, "invalid severity for #{rule.id}: #{severity_value}"
        end
      end
    end

    class Engine
      BLOCKING_DIAGNOSTICS = %w[invalid_hole unknown_part unknown_pin invalid_placement no_free_hole].freeze
      LEVELS = { "info" => 0, "warning" => 1, "error" => 2 }.freeze

      def initialize(config: Config.new)
        @config = config
      end

      def run(paths, only: nil, except: nil)
        Array(paths).filter_map do |path|
          next if excluded?(path)
          begin
            circuit = if path.end_with?(".json")
              Breadkit.load(path)
            else
              document = Breadkit::DSL.load_file(path)
              document.part_paths.concat(@config.extra_parts)
              Breadkit::Resolver.new.call(document)
            end
            offenses = inspect_circuit(circuit, only, except)
            { path: path, offenses: suppress(offenses, circuit.lint_disables) }
          rescue StandardError => e
            offense = Offense.new(rule: "Fatal/EvaluationError", severity: "error", message: e.message,
                                  location: Breadkit::SourceLocation.new(path: path, line: nil), targets: {}, state: nil)
            { path: path, offenses: [offense] }
          end
        end
      end

      def fail?(files, threshold = @config.fail_level)
        minimum = LEVELS.fetch(threshold.to_s, 1)
        files.any? { |file| file[:offenses].any? { |item| LEVELS.fetch(item.severity, 2) >= minimum } }
      end

      def fatal?(files)
        files.any? { |file| file[:offenses].any? { |item| item.rule == "Fatal/EvaluationError" } }
      end

      private

      def inspect_circuit(circuit, only, except)
        offenses = circuit.diagnostics.filter_map do |diagnostic|
          rule_id = diagnostic_rule(diagnostic.code)
          rule = Registry.all.find { |item| item.id == rule_id }
          next unless rule && @config.enabled?(rule) && selected?(rule_id, only, except)
          offense(rule_id, diagnostic.message, diagnostic.location, targets: { components: diagnostic.targets }, state: nil)
        end
        broken_layout = circuit.diagnostics.any? { |item| BLOCKING_DIAGNOSTICS.include?(item.code) }
        states = circuit.states(@config.switch_states)
        Registry.all.each do |rule|
          next unless @config.enabled?(rule) && selected?(rule.id, only, except)
          next if broken_layout && rule.id.start_with?("Electrical/", "Intent/")
          relevant_states = rule.state_sensitive ? states : [states.first]
          relevant_states.each do |state|
            offenses.concat(check_rule(rule, circuit, state))
          end
        end
        offenses.uniq { |item| [item.rule, item.message, item.location&.line, item.state] }
               .sort_by { |item| [item.location&.path.to_s, item.location&.line.to_i, item.rule] }
      end

      def check_rule(rule, circuit, state)
        if rule.is_a?(Class)
          context = Context.new(circuit, state, @config)
          rule.new(@config).check(context)
          return context.offenses
        end
        case rule.checker
        when :same_strip then same_strip(circuit, rule)
        when :short_circuit then short_circuit(circuit, rule, state)
        when :shorted_component then shorted_component(circuit, rule, state)
        when :floating_pin then floating_pins(circuit, rule, state)
        when :dangling_wire then dangling_wires(circuit, rule, state)
        when :split_rail then split_rails(circuit, rule)
        when :missing_series_resistor then missing_series_resistors(circuit, rule, state)
        when :reverse_polarity then reverse_polarity(circuit, rule, state)
        when :power_pin then power_pins(circuit, rule, state)
        when :supply_range then supply_ranges(circuit, rule, state)
        when :common_ground then common_ground(circuit, rule, state)
        when :label_conflict then label_conflicts(circuit, rule, state)
        when :wire_color then wire_colors(circuit, rule)
        when :expectations then expectations(circuit, rule, state)
        else []
        end
      end

      def same_strip(circuit, rule)
        circuit.components.values.flat_map do |component|
          next [] if component.part.placement == "offboard"
          pins = component.pins.values.select(&:hole_id)
          groups = pins.group_by { |pin| circuit.board.hole(pin.hole_id)&.strip_id }
          groups.flat_map do |strip, members|
            next [] unless strip && members.length > 1
            members.combination(2).filter_map do |left, right|
              allowed = Array(component.part.data["same_strip_ok"]).any? do |pair|
                pair = pair.map(&:to_s)
                left_keys = [left.name, left.number]
                right_keys = [right.name, right.number]
                (left_keys & pair).any? && (right_keys & pair).any?
              end
              next if allowed
              message = "#{component.ref} pins #{left.name}, #{right.name} share strip #{strip}"
              offense(rule.id, message, component.location,
                      targets: { components: [component.ref], holes: [left.hole_id, right.hole_id] })
            end
          end
        end
      end

      def short_circuit(circuit, rule, state)
        circuit.potentials(state).conflicts.map do |conflict|
          supply = conflict[:supply]
          path = circuit.shortest_path("#{supply.name}.+", "#{supply.name}.-", state)
          message = "inconsistent voltage constraints near #{conflict[:net]} (#{supply.name}: #{supply.voltage} V; path: #{path.join(' → ')})"
          offense(rule.id, message, supply.location,
                  targets: { nets: [conflict[:net]], holes: path.select { |item| circuit.board.hole(item) },
                             wires: path & circuit.wires.map(&:id) }, state: state.name)
        end
      end

      def shorted_component(circuit, rule, state)
        circuit.components.values.filter_map do |component|
          pins = component.pins.values
          next unless pins.length == 2 && pins.all?(&:hole_id)
          next if circuit.board.hole(pins[0].hole_id).strip_id == circuit.board.hole(pins[1].hole_id).strip_id
          next unless circuit.net_of("#{component.ref}.#{pins[0].name}", state) == circuit.net_of("#{component.ref}.#{pins[1].name}", state)
          offense(rule.id, "#{component.ref} pins are connected to the same net", component.location,
                  targets: { components: [component.ref] }, state: state.name)
        end
      end

      def floating_pins(circuit, rule, state)
        circuit.components.values.flat_map do |component|
          next [] if component.part.placement == "offboard"
          component.pins.values.filter_map do |pin|
            next if component.unused.include?(pin.number) || component.unused.include?(pin.name)
            net = circuit.net_of("#{component.ref}.#{pin.name}", state)
            next unless net
            externally_connected = net.members.any? do |member|
              member != "#{component.ref}.#{pin.name}" &&
                (!member.include?(".") || member.split(".", 2).first != component.ref)
            end
            next if externally_connected
            offense(rule.id, "#{component.ref}.#{pin.name} has no external connection", component.location,
                    targets: { components: [component.ref], holes: [pin.hole_id].compact }, state: state.name)
          end
        end
      end

      def dangling_wires(circuit, rule, state)
        circuit.wires.filter_map do |wire|
          attached = [wire.from, wire.to].map do |endpoint|
            hole = circuit.board.hole(endpoint)
            if hole.nil?
              parsed = HoleId.parse(endpoint) rescue nil
              component = parsed&.kind == :pin && circuit.components[parsed.ref]
              next component&.part&.placement == "offboard"
            end
            circuit.components.values.any? { |component| component.pins.values.any? { |pin| pin.hole_id && circuit.board.hole(pin.hole_id)&.strip_id == hole.strip_id } } ||
              circuit.supplies.any? { |supply| [supply.plus, supply.minus].any? { |id| circuit.board.hole(id)&.strip_id == hole.strip_id } } ||
              circuit.wires.any? { |other| other.id != wire.id && [other.from, other.to].any? { |id| circuit.board.hole(id)&.strip_id == hole.strip_id } }
          end
          next if attached.all?
          offense(rule.id, "#{wire.id} has an unconnected end", wire.location, targets: { wires: [wire.id] }, state: state.name)
        end
      end

      def split_rails(circuit, rule)
        circuit.board.holes.values.select(&:rail).group_by(&:rail).flat_map do |rail, holes|
          segments = holes.group_by(&:strip_id)
          next [] if segments.length < 2
          entries = segments.map do |_strip, segment_holes|
            ids = segment_holes.map(&:id)
            net = circuit.nets.find { |item| !(item.holes & ids).empty? }
            voltage = net && circuit.potentials.values[net.name]
            [segment_holes, net, voltage]
          end
          next [] unless entries.any? { |_holes, _net, voltage| !voltage.nil? }
          entries.filter_map do |segment_holes, net, voltage|
            touched = net&.members&.any? do |member|
              circuit.wires.any? { |wire| wire.id == member } || circuit.components.keys.any? { |ref| member.start_with?("#{ref}.") }
            end
            next unless net && voltage.nil? && touched
            offense(rule.id, "used segment of #{rail} has no supply", nil,
                    targets: { holes: [segment_holes.first.id], nets: [net.name] })
          end
        end
      end

      def missing_series_resistors(circuit, rule, state)
        circuit.components.values.filter_map do |component|
          next unless Array(component.part.data["flags"]).include?("needs_series_resistor")
          polarity = component.part.data["polarity"] || {}
          positive = component.pins[polarity["positive"]]
          negative = component.pins[polarity["negative"]]
          next unless positive && negative
          high = circuit.net_of("#{component.ref}.#{positive.name}", state)
          low = circuit.net_of("#{component.ref}.#{negative.name}", state)
          next unless high && low
          values = circuit.potentials(state).values
          next unless values.key?(high.name) && values.key?(low.name)
          next unless unprotected_path?(circuit, high.name, low.name, component, state)
          offense(rule.id, "#{component.ref} has no current-limiting resistor in series", component.location,
                  targets: { components: [component.ref], nets: [high.name, low.name] }, state: state.name)
        end
      end

      def unprotected_path?(circuit, start, finish, excluded_component, state)
        # ponytail: graph reachability ignores load branches; use full current-path analysis if topology must be proven.
        adjacency = Hash.new { |hash, key| hash[key] = [] }
        circuit.components.each_value do |component|
          next if component == excluded_component || component.pins.length != 2 || current_limiter?(component)
          pins = component.pins.values
          left, right = pins.map { |pin| circuit.net_of("#{component.ref}.#{pin.name}", state)&.name }
          next unless left && right && left != right
          adjacency[left] << right
          adjacency[right] << left
        end
        circuit.supplies.each do |supply|
          left = circuit.net_of("#{supply.name}.+", state)&.name
          right = circuit.net_of("#{supply.name}.-", state)&.name
          next unless left && right
          adjacency[left] << right
          adjacency[right] << left
        end
        seen, queue = { start => true }, [start]
        until queue.empty?
          current = queue.shift
          return true if current == finish
          adjacency[current].each do |target|
            next if seen[target]
            seen[target] = true
            queue << target
          end
        end
        false
      end

      def current_limiter?(component)
        component.part.id == "resistor" && Breadkit::Value.parse(component.value).positive?
      rescue ArgumentError
        false
      end

      def reverse_polarity(circuit, rule, state)
        circuit.components.values.filter_map do |component|
          polarity = component.part.data["polarity"]
          next unless polarity
          positive = component.pins[polarity["positive"]]
          negative = component.pins[polarity["negative"]]
          next unless positive && negative
          high = circuit.net_of("#{component.ref}.#{positive.name}", state)
          low = circuit.net_of("#{component.ref}.#{negative.name}", state)
          values = circuit.potentials(state).values
          next unless high && low && values.key?(high.name) && values.key?(low.name)
          next unless values[high.name] < values[low.name]
          offense(rule.id, "#{component.ref} positive pin is below its negative pin", component.location,
                  targets: { components: [component.ref], nets: [high.name, low.name] }, state: state.name)
        end
      end

      def power_pins(circuit, rule, state)
        grounds = circuit.supplies.filter_map { |supply| circuit.net_of("#{supply.name}.-", state)&.name }
        values = circuit.potentials(state).values
        circuit.components.values.reject { |component| component.part.placement == "offboard" }.flat_map do |component|
          component.pins.values.filter_map do |pin|
            next unless %w[power ground].include?(pin.role)
            net = circuit.net_of("#{component.ref}.#{pin.name}", state)
            voltage = net && values[net.name]
            connected = if pin.role == "ground"
              grounds.include?(net&.name)
            else
              !voltage.nil? && grounds.any? { |name| values.key?(name) && voltage > values[name] }
            end
            next if connected
            offense(rule.id, "#{component.ref}.#{pin.name} is not connected to a valid #{pin.role} supply", component.location,
                    targets: { components: [component.ref], holes: [pin.hole_id].compact }, state: state.name)
          end
        end
      end

      def supply_ranges(circuit, rule, state)
        values = circuit.potentials(state).values
        circuit.components.values.filter_map do |component|
          range = component.part.data["supply_range"]
          next unless range
          power = component.pins.values.find { |pin| pin.role == "power" }
          ground = component.pins.values.find { |pin| pin.role == "ground" }
          next unless power && ground
          high = circuit.net_of("#{component.ref}.#{power.name}", state)
          low = circuit.net_of("#{component.ref}.#{ground.name}", state)
          next unless high && low && values.key?(high.name) && values.key?(low.name)
          voltage = values[high.name] - values[low.name]
          next if voltage >= range[0].to_f && voltage <= range[1].to_f
          offense(rule.id, "#{component.ref} supply is #{voltage.round(3)} V; expected #{range[0]}..#{range[1]} V", component.location,
                  targets: { components: [component.ref], nets: [high.name, low.name] })
        end
      end

      def common_ground(circuit, rule, state)
        return [] if circuit.supplies.length < 2
        result = circuit.potentials(state)
        grounds = circuit.supplies.filter_map { |supply| circuit.net_of("#{supply.name}.-", state)&.name }.uniq
        groups = grounds.map { |name| result.components.index { |component| component.include?(name) } }.uniq
        return [] if groups.length <= 1
        [offense(rule.id, "power supplies do not share a ground", nil, targets: { nets: grounds })]
      end

      def wire_colors(circuit, rule)
        positive = Array(@config.data.dig(rule.id, "PositiveColors") || %w[red orange]).map { |color| color.downcase }
        ground = Array(@config.data.dig(rule.id, "GroundColors") || %w[black blue]).map { |color| color.downcase }
        circuit.wires.filter_map do |wire|
          net = circuit.nets.find { |item| item.members.include?(wire.id) }
          voltage = net && circuit.potentials.values[net.name]
          expected = voltage&.positive? ? positive : (voltage == 0.0 ? ground : nil)
          next unless expected && wire.color && !expected.include?(wire.color.downcase)
          offense(rule.id, "#{wire.id} uses #{wire.color}; expected #{expected.join(' or ')}", wire.location,
                  targets: { wires: [wire.id], nets: [net.name] })
        end
      end

      def label_conflicts(circuit, rule, state)
        circuit.nets(state).filter_map do |net|
          next unless net.labels.length > 1
          offense(rule.id, "net has conflicting labels: #{net.labels.join(', ')}", nil, targets: { nets: [net.name] }, state: state.name)
        end
      end

      def expectations(circuit, rule, state)
        return [] if rule.id == "Intent/UnknownNet" && circuit.diagnostics.any? { |item| item.code == "unknown_net" }
        circuit.expectations.flat_map do |expectation|
          strict = expectation["strict"] || expectation[:strict]
          Array(expectation["entries"] || expectation[:entries]).filter_map do |item|
            kind = item["kind"] || item[:kind]
            refs = item["refs"] || item[:refs] || []
            loc = item["location"] || item[:location]
            names = refs.map(&:to_s)
            nets = names.map { |reference| circuit.net_of(reference, state) }
            if nets.any?(&:nil?)
              next unless rule.id == "Intent/UnknownNet"
              offense(rule.id, "unknown reference in expectation: #{names.join(', ')}", location_from(loc), targets: {})
            elsif rule.id == "Intent/ConnectionMismatch" && kind == "connected" && nets.map(&:name).uniq.length > 1
              offense(rule.id, "expected #{names.join(', ')} to be connected", location_from(loc), targets: { nets: nets.map(&:name) }, state: state.name)
            elsif rule.id == "Intent/ConnectionMismatch" && kind == "isolated" && nets.map(&:name).uniq.length != names.length
              offense(rule.id, "expected #{names.join(', ')} to be isolated", location_from(loc), targets: { nets: nets.map(&:name) }, state: state.name)
            elsif rule.id == "Intent/ConnectionMismatch" && kind == "net"
              actual_pins = nets.compact.flat_map(&:members).select do |member|
                circuit.components.keys.any? { |ref| member.start_with?("#{ref}.") }
              end.uniq
              extra_pins = strict ? actual_pins - names : []
              next if nets.map(&:name).uniq.length == 1 && extra_pins.empty?
              detail = extra_pins.empty? ? "expected #{names.join(', ')} on one net" : "undeclared pins on expected net: #{extra_pins.join(', ')}"
              offense(rule.id, detail, location_from(loc), targets: { nets: nets.compact.map(&:name), components: extra_pins.map { |pin| pin.split('.', 2).first } }, state: state.name)
            end
          end
        end
      end

      def diagnostic_rule(code)
        return "Intent/UnknownNet" if code == "unknown_net"
        Registry.all.find { |rule| rule.checker == :diagnostic && rule.id.split("/").last.gsub(/([a-z])([A-Z])/, '\\1_\\2').downcase == code }&.id
      end

      def offense(rule_id, message, location, targets: {}, state: nil)
        rule = Registry.all.find { |item| item.id == rule_id }
        Offense.new(rule: rule_id, severity: rule ? @config.severity(rule) : "error", message: message,
                    location: location, targets: targets, state: state)
      end

      def selected?(id, only, except)
        return false if only && !only.include?(id)
        return false if except && except.include?(id)
        true
      end

      def excluded?(path)
        @config.excluded?(path)
      end

      def suppress(offenses, disables)
        offenses.reject do |item|
          disables.any? do |disable|
            rule = disable[:rule] || disable["rule"]
            target = disable[:on] || disable["on"]
            rule == item.rule && (!target || item.targets.values.flatten.include?(target))
          end
        end
      end

      def location_from(value)
        return value if value.is_a?(SourceLocation)
        return nil unless value
        SourceLocation.new(path: value["path"] || value[:path], line: value["line"] || value[:line])
      end
    end

    class Formatter
      def text(files, locale: "en")
        lines = files.flat_map do |file|
          file[:offenses].map do |item|
            level = { "error" => "E", "warning" => "W", "info" => "I" }.fetch(item.severity, "E")
            state = item.state ? " (#{item.state} state)" : ""
            "#{file[:path]}:#{item.location&.line || 1}: #{level}: [#{item.rule}] #{item.message}#{state}"
          end
        end
        errors, warnings, infos = files.flat_map { |file| file[:offenses] }.group_by(&:severity).values_at("error", "warning", "info").map { |items| items ? items.length : 0 }
        summary = if locale == "ja"
          "#{files.length} ファイルを検査、#{errors + warnings + infos} 件の指摘（エラー #{errors} 件、警告 #{warnings} 件）"
        else
          "#{files.length} files inspected, #{errors + warnings + infos} offenses (#{errors} errors, #{warnings} warnings)"
        end
        (lines + [summary]).join("\n")
      end

      def json(files)
        offenses = files.flat_map { |file| file[:offenses] }
        JSON.pretty_generate(
          schema_version: 1,
          tool: { name: "bklint", version: VERSION },
          files: files.map do |file|
            { path: File.expand_path(file[:path]), offenses: file[:offenses].map do |item|
              { rule: item.rule, severity: item.severity, message: item.message,
                location: { line: item.location&.line }, state: item.state, targets: item.targets }
            end }
          end,
          summary: { files: files.length, errors: offenses.count { |item| item.severity == "error" },
                     warnings: offenses.count { |item| item.severity == "warning" }, infos: offenses.count { |item| item.severity == "info" } }
        )
      end

      def github(files)
        files.flat_map do |file|
          file[:offenses].map do |item|
            level = { "error" => "error", "warning" => "warning", "info" => "notice" }.fetch(item.severity, "error")
            line = item.location&.line || 1
            message = item.message.gsub("%", "%25").gsub("\r", "%0D").gsub("\n", "%0A")
            "::#{level} file=#{file[:path]},line=#{line},title=#{item.rule}::#{message}"
          end
        end.join("\n")
      end

      def sarif(files)
        rules = (Registry.all.map do |rule|
          definition = { id: rule.id, shortDescription: { text: rule.description } }
          path = File.expand_path("../../docs/rules/#{rule.id}.md", __dir__)
          definition[:helpUri] = "docs/rules/#{rule.id}.md" if File.file?(path)
          definition
        end + [{ id: "Fatal/EvaluationError", shortDescription: { text: "The input could not be evaluated." } }])
        results = files.flat_map do |file|
          file[:offenses].map do |item|
            result = { ruleId: item.rule, level: { "error" => "error", "warning" => "warning", "info" => "note" }.fetch(item.severity, "error"),
                       message: { text: item.message }, properties: { targets: item.targets, state: item.state } }
            if item.location&.line
              result[:locations] = [{ physicalLocation: { artifactLocation: { uri: file[:path] }, region: { startLine: item.location.line } } }]
            end
            result
          end
        end
        JSON.pretty_generate(version: "2.1.0", "$schema" => "https://json.schemastore.org/sarif-2.1.0.json",
                             runs: [{ tool: { driver: { name: "bklint", version: VERSION, rules: rules } }, results: results }])
      end
    end

    class CLI
      def run(argv)
        options = { format: "text", fail_level: nil }
        parser = OptionParser.new do |opts|
          opts.banner = "Usage: bklint [options] [FILES...]"
          opts.on("-f", "--format FORMAT", %w[text json github sarif]) { |value| options[:format] = value }
          opts.on("-o", "--out PATH") { |value| options[:out] = value }
          opts.on("-c", "--config PATH") { |value| options[:config] = value }
          opts.on("--fail-level LEVEL", %w[error warning info]) { |value| options[:fail_level] = value }
          opts.on("--only RULES") { |value| options[:only] = value.split(",") }
          opts.on("--except RULES") { |value| options[:except] = value.split(",") }
          opts.on("--switch-states MODE", %w[none single all]) { |value| options[:switch_states] = value }
          opts.on("--list-rules") { options[:list_rules] = true }
          opts.on("--explain RULE") { |value| options[:explain] = value }
          opts.on("--locale LOCALE", %w[ja en]) { |value| options[:locale] = value }
          opts.on("-v", "--version") { puts "bklint #{VERSION}"; return 0 }
          opts.on("-h", "--help") { puts opts; return 0 }
        end
        parser.parse!(argv)
        locale = options[:locale] || (ENV["LANG"].to_s.start_with?("ja") ? "ja" : "en")
        return list_rules(locale) if options[:list_rules]
        return explain(options[:explain], locale) if options[:explain]
        config_path = options[:config] || (File.file?(".bklint.yml") ? ".bklint.yml" : nil)
        config = Config.new(config_path)
        config.unknown_rules.each do |rule|
          suggestion = DidYouMean::SpellChecker.new(dictionary: Registry.all.map(&:id)).correct(rule).first
          warn "bklint: unknown rule #{rule.inspect}#{suggestion ? "; did you mean #{suggestion.inspect}?" : ""}"
        end
        config.data["AllRules"] ||= {}
        config.data["AllRules"]["SwitchStates"] = options[:switch_states] if options[:switch_states]
        files = argv.empty? ? Dir.glob("**/*.bk.rb").reject { |path| path.split(File::SEPARATOR).any? { |part| part.start_with?(".") } } : argv
        results = Engine.new(config: config).run(files, only: options[:only], except: options[:except])
        formatter = Formatter.new
        output = case options[:format]
        when "json" then formatter.json(results)
        when "github" then formatter.github(results)
        when "sarif" then formatter.sarif(results)
        else formatter.text(results, locale: locale)
        end
        options[:out] ? File.write(options[:out], output + "\n") : puts(output)
        return 2 if Engine.new(config: config).fatal?(results)
        Engine.new(config: config).fail?(results, options[:fail_level] || config.fail_level) ? 1 : 0
      rescue OptionParser::ParseError, Error, Psych::Exception, SystemCallError, LoadError => e
        warn "bklint: #{e.message}"
        2
      end

      private

      def list_rules(locale)
        Registry.all.each { |rule| puts "#{rule.id}\t#{rule.severity}\t#{localized_description(rule, locale)}" }
        0
      end

      def explain(id, locale)
        rule = Registry.all.find { |item| item.id == id }
        raise Error, "unknown rule #{id}" unless rule
        path = File.expand_path("../../docs/rules/#{rule.id}.md", __dir__)
        puts File.file?(path) ? File.read(path) : "#{rule.id} (#{rule.severity})\n#{localized_description(rule, locale)}"
        0
      end

      def localized_description(rule, locale)
        path = File.expand_path("../../locales/#{locale}.yml", __dir__)
        translations = YAML.safe_load(File.read(path), aliases: false) || {}
        translations.dig("rules", rule.id) || rule.description
      rescue Errno::ENOENT, Psych::Exception
        rule.description
      end
    end
  end
end
