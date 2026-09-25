# frozen_string_literal: true

require "optparse"

module Breadkit
  module Render
    class CLI
      def run(argv)
        options = { scale: 2.0, theme: "light", color_by: "wire", crop: "auto", backend: "auto", quality: 90 }
        parser = OptionParser.new do |opts|
          opts.banner = "Usage: bkrender [options] INPUT"
          opts.on("-o", "--output PATH") { |value| options[:output] = value }
          opts.on("-f", "--format FORMAT", %w[svg png jpeg jpg]) { |value| options[:format] = value == "jpg" ? "jpeg" : value }
          opts.on("--scale N", Float) { |value| options[:scale] = value }
          opts.on("--theme NAME", %w[light dark print]) { |value| options[:theme] = value }
          opts.on("--color-by MODE", %w[wire net]) { |value| options[:color_by] = value }
          opts.on("--show-nets") { options[:show_nets] = true }
          opts.on("--legend") { options[:legend] = true }
          opts.on("--crop MODE", %w[auto none]) { |value| options[:crop] = value }
          opts.on("--annotations FILE") { |value| options[:annotations] = value }
          opts.on("--backend NAME", %w[auto rsvg vips magick]) { |value| options[:backend] = value }
          opts.on("--background COLOR") { |value| options[:background] = value }
          opts.on("--quality N", Integer) { |value| options[:quality] = value }
          opts.on("--force") { options[:force] = true }
          opts.on("-v", "--version") { puts "bkrender #{VERSION}"; return 0 }
          opts.on("-h", "--help") { puts opts; return 0 }
        end
        parser.parse!(argv)
        input = argv.shift
        raise ArgumentError, "input file required\n#{parser}" unless input
        raise ArgumentError, "unexpected arguments: #{argv.join(' ')}" unless argv.empty?
        format = output_format(options)
        circuit = Breadkit.load(input)
        errors = circuit.diagnostics.select { |item| item.severity == "error" }
        if !errors.empty? && !options[:force]
          errors.each { |item| warn "#{item.location&.path}:#{item.location&.line}: #{item.message}" }
          return 1
        end
        svg = SvgRenderer.new.render(circuit, crop: options[:crop], theme: options[:theme],
                                    show_nets: options[:show_nets], legend: options[:legend], color_by: options[:color_by],
                                    annotations: read_annotations(options[:annotations], input))
        output = if format == "svg"
          svg
        else
          Rasterizer.new.rasterize(svg, format: format, scale: options[:scale],
                                   background: options[:background] || "white", quality: options[:quality], backend: options[:backend])
        end
        options[:output] ? File.binwrite(options[:output], output) : $stdout.write(output)
        0
      rescue OptionParser::ParseError, ArgumentError, JSON::ParserError, Breadkit::Error, Error => e
        warn "bkrender: #{e.message}"
        2
      rescue StandardError => e
        warn "bkrender: #{e.message}"
        2
      end

      private

      def output_format(options)
        extension = File.extname(options[:output].to_s).downcase
        from_path = { ".svg" => "svg", ".png" => "png", ".jpg" => "jpeg", ".jpeg" => "jpeg" }[extension]
        raise ArgumentError, "unsupported output extension: #{extension}" if options[:output] && !from_path
        if options[:format] && from_path && options[:format] != from_path
          raise ArgumentError, "--format conflicts with output extension"
        end
        options[:format] || from_path || "svg"
      end

      def read_annotations(path, input)
        return [] unless path
        data = JSON.parse(File.read(path))
        raise ArgumentError, "unsupported lint JSON schema_version" unless data["schema_version"] == 1
        files = Array(data["files"])
        match = files.find { |file| File.expand_path(file["path"].to_s) == File.expand_path(input) }
        match ||= files.first if files.length == 1
        Array(match && match["offenses"])
      end
    end
  end
end
