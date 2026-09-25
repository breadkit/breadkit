# frozen_string_literal: true

module Breadkit
  module Render
    class Rasterizer
      def rasterize(svg, format:, scale: 2.0, background: "white", quality: 90, backend: "auto")
        format = format.to_s
        backend = backend.to_s
        raise Error, "unsupported raster format: #{format}" unless %w[png jpeg].include?(format)
        raise Error, "unsupported raster backend: #{backend}" unless %w[auto rsvg vips magick].include?(backend)

        begin
          scale = Float(scale)
        rescue ArgumentError, TypeError
          raise Error, "scale must be a positive finite number"
        end
        raise Error, "scale must be a positive finite number" unless scale.finite? && scale.positive?
        raise Error, "quality must be an integer between 0 and 100" unless quality.is_a?(Integer) && quality.between?(0, 100)
        background = color(background) if format == "jpeg"

        candidates = case backend
        when "rsvg" then ["rsvg"]
        when "magick" then ["magick"]
        when "vips" then ["vips"]
        else format == "png" ? %w[rsvg vips magick] : %w[vips magick]
        end
        candidates.each do |name|
          next unless supports?(name, format)
          begin
            return send(name, svg, format, scale, background, quality)
          rescue Error
            raise if backend != "auto"
          end
        end
        raise Error, "no raster backend found for #{format}; install librsvg (brew install librsvg / apt install librsvg2-bin) or ImageMagick"
      end

      private

      def supports?(name, format)
        return !!executable("rsvg-convert") if name == "rsvg" && format == "png"
        return !!executable("magick") || !!executable("convert") if name == "magick"
        return false unless name == "vips"
        require "vips"
        true
      rescue LoadError
        false
      end

      def rsvg(svg, _format, scale, _background, _quality)
        stdout, stderr, status = Open3.capture3(executable("rsvg-convert"), "--format=png", "--zoom=#{scale}", stdin_data: svg, binmode: true)
        raise Error, "rsvg-convert failed: #{stderr}" unless status.success?
        stdout
      end

      def magick(svg, format, scale, background, quality)
        command = executable("magick") || executable("convert")
        args = []
        font = font_file
        args.concat(["-font", font]) if font
        args += ["svg:-", "-resize", "#{(scale.to_f * 100).round}%"]
        args += ["-background", "##{background.map { |channel| channel.to_s(16).rjust(2, "0") }.join}", "-alpha", "remove"] if format == "jpeg"
        args += ["-quality", quality.to_s] if format == "jpeg"
        args << "#{format}:-"
        stdout, stderr, status = Open3.capture3(command, *args, stdin_data: svg, binmode: true)
        raise Error, "ImageMagick failed: #{stderr}" unless status.success?
        stdout
      end

      def vips(svg, format, scale, background, quality)
        image = Vips::Image.svgload_buffer(svg, scale: scale.to_f)
        if format == "jpeg"
          image = image.flatten(background: background) if image.has_alpha?
          image.jpegsave_buffer(Q: quality.to_i)
        else
          image.pngsave_buffer
        end
      rescue StandardError => e
        raise Error, "libvips failed: #{e.message}"
      end

      def color(value)
        named = { "white" => [255, 255, 255], "black" => [0, 0, 0] }
        name = value.to_s.downcase
        return named[name] if named.key?(name)

        hex = value.to_s.delete_prefix("#")
        raise Error, "unsupported JPEG background color: #{value}; use white, black, #RGB, or #RRGGBB" unless /\A(?:[0-9a-f]{3}|[0-9a-f]{6})\z/i.match?(hex)

        hex = hex.chars.map { |char| char * 2 }.join if hex.length == 3
        hex.scan(/../).map { |part| part.to_i(16) }
      end

      def executable(name)
        ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).map { |dir| File.join(dir, name) }.find { |path| File.executable?(path) }
      end

      def font_file
        candidates = if RbConfig::CONFIG["host_os"].match?(/darwin/i)
          ["/System/Library/Fonts/Supplemental/Arial Unicode.ttf", "/System/Library/Fonts/Supplemental/Arial.ttf"]
        elsif RbConfig::CONFIG["host_os"].match?(/mswin|mingw/i)
          ["C:/Windows/Fonts/arial.ttf"]
        else
          ["/usr/share/fonts/truetype/noto/NotoSansCJK-Regular.ttc", "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"]
        end
        candidates.find { |path| File.file?(path) }
      end
    end
  end
end
