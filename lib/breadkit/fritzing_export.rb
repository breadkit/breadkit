# frozen_string_literal: true

require "cgi/escape"

module Breadkit
  # Writes a Fritzing .fz sketch for the exact 830-hole full breadboard and its jumpers.
  class FritzingExport
    BOARD_PART = "Breadboard-RSR03MB102-ModuleID"
    VIEWS = [["breadboardView", "breadboardbreadboard", "breadboardWire"],
             ["pcbView", "breadboardbreadboard", "copper1trace"],
             ["schematicView", "breadboardbreadboard", "schematicTrace"]].freeze
    COLORS = { "red" => "#ff0000", "black" => "#000000", "green" => "#008000",
               "blue" => "#0000ff", "yellow" => "#ffff00", "white" => "#ffffff",
               "orange" => "#ffa500" }.freeze
    RAILS = { "T+" => ["Y", 14.4], "T-" => ["Z", 7.2],
              "B+" => ["W", 144.0], "B-" => ["X", 136.8] }.freeze
    # The official breadboard2.svg uses Illustrator's 72 dpi pixel dimensions.
    # Fritzing's scene uses 90 dpi, unlike the SVG's own coordinate system.
    BOARD_SCALE = 90.0 / 72
    RED_LED_PART = "LED-genedb611bf8177f41ac9c325217070f0c62ColorLEDModuleID"
    PARTS = { "resistor" => ["ResistorModuleID", "resistor.fzp"],
              "led" => [RED_LED_PART, "LED-generic-5mm_6852162_005.fzp"],
              "tact_switch_6mm" => ["20A9BBEE34_ST", "pushbutton_4_horizontal.fzp"] }.freeze

    def self.call(circuit)
      new(circuit).call
    end

    def initialize(circuit)
      @circuit = circuit
    end

    def call
      validate!
      links = Hash.new { |hash, key| hash[key] = [] }
      components = circuit.components.values.each_with_index.map do |component, offset|
        index = offset + 2
        plan = part_plan(component)
        plan.fetch(:pins).each do |connector, location|
          links[location.first] << [index, connector, :part]
        end
        part_instance(component, index, plan)
      end
      wires = circuit.wires.each_with_index.map do |wire, index|
        endpoints = [wire.from, wire.to].map { |reference| terminal(reference) }
        model_index = index + components.length + 2
        endpoints.each_with_index { |(pin, _x, _y), side| links[pin] << [model_index, "connector#{side}", :wire] }
        wire_instance(wire, model_index, endpoints)
      end
      <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <module fritzingVersion="1.0.8" icon=".png">
          <views>
            <view name="breadboardView" backgroundColor="#ffffff" gridSize="0.1in" showGrid="1" alignToGrid="1" viewFromBelow="0"/>
            <view name="schematicView" backgroundColor="#ffffff" gridSize="0.1in" showGrid="1" alignToGrid="1" viewFromBelow="0"/>
            <view name="pcbView" backgroundColor="#333333" gridSize="0.05in" showGrid="1" alignToGrid="1" viewFromBelow="0"/>
          </views>
          <instances>
        #{board_instance(links)}
        #{components.join("\n")}
        #{wires.join("\n")}
          </instances>
        </module>
      XML
    end

    private

    attr_reader :circuit

    def validate!
      standard = BoardDef.load("full").data
      unless !circuit.multi_board? && circuit.board.definition.data == standard && !circuit.board.split_rails
        raise ArgumentError, "Fritzing export supports only the standard unsplit full board"
      end
      raise ArgumentError, "Fritzing export does not support standalone supplies" unless circuit.supplies.empty?
      raise ArgumentError, "Fritzing export does not support net labels" unless circuit.labels.empty?

      circuit.components.each_value { |component| part_plan(component) }

      circuit.wires.each do |wire|
        unless wire.electrical && wire.route == "straight" && Array(wire.layer).empty? && !wire.dashed
          raise ArgumentError, "Fritzing export supports only straight electrical jumpers without layers or dashes (#{wire.id})"
        end
        color(wire.color)
      end
    end

    def terminal(reference)
      hole = circuit.board.hole(reference)
      raise ArgumentError, "Fritzing export requires a board hole, got #{reference}" unless hole

      if hole.kind == :terminal
        ["pin#{hole.col}#{hole.row.upcase}", (10.92 + (hole.col - 1) * 7.2) * BOARD_SCALE,
         (115.2 - hole.y * 7.2) * BOARD_SCALE]
      else
        rail, y = RAILS.fetch(hole.rail) { raise ArgumentError, "Fritzing export does not support rail #{hole.rail}" }
        number = 3 + hole.col - 1 + ((hole.col - 1) / 5)
        ["pin#{number}#{rail}", (10.92 + (number - 1) * 7.2) * BOARD_SCALE, y * BOARD_SCALE]
      end
    end

    def part_plan(component)
      id = component.part.id
      part = PARTS[id]
      raise ArgumentError, "Fritzing export has unsupported part #{component.ref} (#{id})" unless part
      if component.attrs[:rotate].to_i != 0 || component.attrs[:mirror]
        raise ArgumentError, "Fritzing export does not support rotated or mirrored #{component.ref}"
      end

      names = case id
      when "resistor" then { "connector0" => "1", "connector1" => "2" }
      when "led" then { "connector0" => "cathode", "connector1" => "anode" }
      else { "connector0" => "2", "connector1" => "1", "connector2" => "4", "connector3" => "3" }
      end
      pins = names.to_h do |connector, name|
        pin = component.pin(name)
        hole = pin && circuit.board.hole(pin.hole_id)
        unless hole&.kind == :terminal
          raise ArgumentError, "Fritzing export needs #{component.ref}.#{name} in a terminal hole"
        end
        [connector, terminal(hole.id)]
      end
      case id
      when "resistor"
        if pins.fetch("connector0")[2] != pins.fetch("connector1")[2] ||
           pins.fetch("connector0")[1] >= pins.fetch("connector1")[1]
          raise ArgumentError, "Fritzing export requires #{component.ref} pins 1 and 2 left-to-right in one row"
        end
        unless component.value.to_s.match?(/\A\d+(?:\.\d+)?(?:[kMmunp])?\z/)
          raise ArgumentError, "Fritzing export needs a plain resistance value for #{component.ref}"
        end
      when "led"
        unless component.attrs.fetch(:color, "red").to_s.casecmp?("red")
          raise ArgumentError, "Fritzing export currently supports only a red LED (#{component.ref})"
        end
        if pins.fetch("connector0")[2] != pins.fetch("connector1")[2]
          raise ArgumentError, "Fritzing export requires #{component.ref} leads in one row"
        end
      else
        top_left, bottom_left, top_right, bottom_right = pins.values_at(*%w[connector0 connector1 connector2 connector3])
        unless (top_right[1] - top_left[1] - 18).abs < 0.001 && bottom_right[1] == top_right[1] &&
               bottom_left[1] == top_left[1] && top_left[2] == top_right[2] &&
               (bottom_left[2] - top_left[2] - 27).abs < 0.001 && bottom_right[2] == bottom_left[2]
          raise ArgumentError, "Fritzing export requires #{component.ref} to straddle the gap on a 2-by-3 hole footprint"
        end
      end
      { id: part[0], path: part[1], type: id, pins: pins }
    end

    def part_instance(component, index, plan)
      pins = plan.fetch(:pins)
      x, y, anchors, mirror_width = part_geometry(plan)
      properties = case plan.fetch(:type)
      when "resistor"
        %(<property name="resistance" value="#{CGI.escapeHTML(component.value.to_s)}"/>) +
          %(<property name="pin spacing" value="400 mil"/>)
      when "led" then %(<property name="color" value="Red (633nm)"/>)
      else ""
      end
      views = VIEWS.map do |view, _board_layer, _wire_layer|
        layer = part_layer(view)
        transform = mirror_width ? %(<transform m11="-1" m12="0" m13="0" m21="0" m22="1" m23="0" m31="#{point(mirror_width)}" m32="0" m33="1"/>) : ""
        geometry = %(<geometry z="2.5" x="#{point(x)}" y="#{point(y)}">#{transform}</geometry>)
        connectors = pins.map do |connector, (pin, target_x, target_y)|
          anchor_x, anchor_y = anchors.fetch(connector)
          tip_x = target_x - x - (mirror_width ? mirror_width - anchor_x : anchor_x)
          tip_x = -tip_x if mirror_width
          tip_y = target_y - y - anchor_y
          leg = if view == "breadboardView" && plan.fetch(:type) != "tact_switch_6mm"
            %(<leg><point x="0" y="0"/><bezier/><point x="#{point(tip_x)}" y="#{point(tip_y)}"/><bezier/></leg>)
          else
            ""
          end
          %(<connector connectorId="#{connector}" layer="#{layer}"><geometry x="#{point(anchor_x)}" y="#{point(anchor_y)}"/>) +
            %(#{leg}<connects><connect connectorId="#{pin}" modelIndex="1" layer="breadboardbreadboard"/></connects></connector>)
        end.join
        %(<#{view} layer="#{layer}">#{geometry}<connectors>#{connectors}</connectors></#{view}>)
      end.join
      %(<instance moduleIdRef="#{plan.fetch(:id)}" modelIndex="#{index}" path="#{plan.fetch(:path)}">) +
        %(#{properties}<title>#{CGI.escapeHTML(component.ref)}</title><views>#{views}</views></instance>)
    end

    def part_geometry(plan)
      pins = plan.fetch(:pins)
      case plan.fetch(:type)
      when "resistor"
        left, right = pins.values_at("connector0", "connector1")
        [(left[1] + right[1]) / 2 - 19.313, left[2] - 4.541,
         { "connector0" => [2.619, 4.541], "connector1" => [36.006, 4.541] }, false]
      when "led"
        cathode, anode = pins.values_at("connector0", "connector1")
        [(cathode[1] + anode[1]) / 2 - 9.660, cathode[2] - 55,
         { "connector0" => [5.658, 36.509], "connector1" => [14.661, 36.509] },
         anode[1] < cathode[1] ? 19.320 : nil]
      else
        top_left, bottom_left = pins.values_at("connector0", "connector1")
        [top_left[1] - 2.171, (top_left[2] + bottom_left[2]) / 2 - 14.852,
         { "connector0" => [19.895, 1.914], "connector1" => [19.895, 27.789],
           "connector2" => [1.895, 1.914], "connector3" => [1.895, 27.789] }, 22.066]
      end
    end

    def part_layer(view)
      case view
      when "breadboardView" then "breadboard"
      when "schematicView" then "schematic"
      else "copper0"
      end
    end

    def board_instance(links)
      views = VIEWS.map do |view, board_layer, wire_layer|
        connectors = links.sort.map do |pin, wires|
          connects = wires.map do |index, connector, type|
            layer = type == :wire ? wire_layer : part_layer(view)
            %(<connect connectorId="#{connector}" modelIndex="#{index}" layer="#{layer}"/>)
          end.join
          %(<connector connectorId="#{pin}" layer="#{board_layer}"><geometry x="0" y="0"/><connects>#{connects}</connects></connector>)
        end.join
        %(<#{view} layer="#{board_layer}"><geometry z="1.5" x="0" y="0"/><connectors>#{connectors}</connectors></#{view}>)
      end.join
      %(<instance moduleIdRef="#{BOARD_PART}" modelIndex="1" path="breadboard2.fzp"><title>Breadboard</title><views>#{views}</views></instance>)
    end

    def wire_instance(wire, index, endpoints)
      first, last = endpoints
      views = VIEWS.map do |view, board_layer, wire_layer|
        geometry = %(<geometry z="3.5" x="#{point(first[1])}" y="#{point(first[2])}" x1="0" y1="0" ) +
                   %(x2="#{point(last[1] - first[1])}" y2="#{point(last[2] - first[2])}" wireFlags="64"/>)
        connectors = endpoints.each_with_index.map do |(pin, _x, _y), side|
          %(<connector connectorId="connector#{side}" layer="#{wire_layer}"><geometry x="0" y="0"/>) +
            %(<connects><connect connectorId="#{pin}" modelIndex="1" layer="#{board_layer}"/></connects></connector>)
        end.join
        %(<#{view} layer="#{wire_layer}">#{geometry}<wireExtras mils="22.2222" color="#{color(wire.color)}" opacity="1" banded="0"/>) +
          %(<connectors>#{connectors}</connectors></#{view}>)
      end.join
      %(<instance moduleIdRef="WireModuleID" modelIndex="#{index}" path="wire.fzp"><title>#{CGI.escapeHTML(wire.id)}</title>) +
        %(<views>#{views}</views></instance>)
    end

    def color(value)
      return "#404040" unless value

      text = value.to_s.downcase
      return COLORS.fetch(text) if COLORS.key?(text)
      return text if text.match?(/\A#[0-9a-f]{6}\z/)

      raise ArgumentError, "Fritzing export supports only basic wire colors or #RRGGBB"
    end

    def point(value)
      format("%.3f", value)
    end
  end
end
