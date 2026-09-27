# frozen_string_literal: true

module Breadkit
  class WireSuggestions
    def initialize(circuit)
      @circuit = circuit
    end

    def call
      return [] if circuit.diagnostics.any? { |item| item.severity == "error" }
      return [] unless circuit.potentials.conflicts.empty?

      occupied = occupied_holes
      bodies = component_bodies
      proposed_nets = UnionFind.new
      proposed_potentials = {}
      circuit.expectations.flat_map do |group|
        next [] if group[:when] || group["when"]

        Array(group[:entries] || group["entries"]).filter_map do |entry|
          next unless (entry[:kind] || entry["kind"]) == "connected"

          refs = Array(entry[:refs] || entry["refs"]).map(&:to_s)
          next unless refs.length == 2

          first, second = refs.map { |ref| placed_pin_hole(ref) }
          next unless first && second
          left_net, right_net = refs.map { |ref| circuit.net_of(ref) }
          next unless left_net && right_net && left_net != right_net

          left_root = proposed_nets.find(left_net.name)
          right_root = proposed_nets.find(right_net.name)
          next if left_root == right_root

          left_potential = proposed_potentials.fetch(left_root, left_net.potential)
          right_potential = proposed_potentials.fetch(right_root, right_net.potential)
          next if left_potential && right_potential && (left_potential - right_potential).abs > 1e-9

          left = free_strip_holes(first, occupied, bodies)
          right = free_strip_holes(second, occupied, bodies)
          next if left.empty? || right.empty?

          from, to = left.product(right).min_by do |a, b|
            [(a.x - b.x)**2 + (a.y - b.y)**2, a.x, a.y, b.x, b.y, a.id, b.id]
          end
          occupied[from.id] = true
          occupied[to.id] = true
          proposed_nets.union(left_root, right_root)
          proposed_potentials[proposed_nets.find(left_root)] = left_potential || right_potential
          { from: from.id, to: to.id, refs: refs }
        end
      end.uniq
    end

    private

    attr_reader :circuit

    def placed_pin_hole(reference)
      parsed = HoleId.parse(reference, board: circuit.board)
      return unless parsed.kind == :pin

      hole_id = circuit.components[parsed.ref]&.pin(parsed.pin)&.hole_id
      hole_id if hole_id && circuit.board.hole(hole_id)
    rescue ArgumentError
      nil
    end

    def free_strip_holes(pin_hole, occupied, bodies)
      Array(circuit.board.strip(pin_hole)).filter_map { |id| circuit.board.hole(id) }
        .reject { |hole| occupied[hole.id] || bodies.any? { |body| covered?(hole, body) } }
    end

    def occupied_holes
      ids = circuit.components.values.flat_map { |component| component.pins.values.filter_map(&:hole_id) }
      ids.concat(circuit.supplies.flat_map { |supply| [supply.plus, supply.minus] })
      circuit.wires.each do |wire|
        next if wire.electrical == false

        [wire.from, wire.to].each do |endpoint|
          hole = circuit.board.hole(endpoint)
          ids << hole.id if hole
        end
      end
      ids.to_h { |id| [id, true] }
    end

    def component_bodies
      circuit.components.values.filter_map do |component|
        component.body_bounds(circuit.board)
      end
    end

    def covered?(hole, bounds)
      left, top, width, height = bounds
      hole.x > left + 1e-6 && hole.x < left + width - 1e-6 &&
        hole.y > top + 1e-6 && hole.y < top + height - 1e-6
    end
  end

  class Circuit
    def wire_suggestions
      WireSuggestions.new(self).call
    end
  end
end
