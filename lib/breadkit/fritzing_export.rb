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

    def self.call(circuit)
      new(circuit).call
    end

    def initialize(circuit)
      @circuit = circuit
    end

    def call
      validate!
      links = Hash.new { |hash, key| hash[key] = [] }
      wires = circuit.wires.each_with_index.map do |wire, index|
        endpoints = [wire.from, wire.to].map { |reference| terminal(reference) }
        endpoints.each_with_index { |(pin, _x, _y), side| links[pin] << [index + 2, side] }
        wire_instance(wire, index + 2, endpoints)
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

      unsupported = circuit.components.values.first
      raise ArgumentError, "Fritzing export has unsupported part #{unsupported.ref} (#{unsupported.part.id})" if unsupported

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
        ["pin#{hole.col}#{hole.row.upcase}", 10.92 + (hole.col - 1) * 7.2, 115.2 - hole.y * 7.2]
      else
        rail, y = RAILS.fetch(hole.rail) { raise ArgumentError, "Fritzing export does not support rail #{hole.rail}" }
        number = 3 + hole.col - 1 + ((hole.col - 1) / 5)
        ["pin#{number}#{rail}", 10.92 + (number - 1) * 7.2, y]
      end
    end

    def board_instance(links)
      views = VIEWS.map do |view, board_layer, wire_layer|
        connectors = links.sort.map do |pin, wires|
          connects = wires.map do |index, side|
            %(<connect connectorId="connector#{side}" modelIndex="#{index}" layer="#{wire_layer}"/>)
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
