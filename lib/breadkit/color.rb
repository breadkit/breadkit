# frozen_string_literal: true

module Breadkit
  module Color
    NAMES = %w[
      aliceblue antiquewhite aqua aquamarine azure beige bisque black blanchedalmond blue blueviolet brown
      burlywood cadetblue chartreuse chocolate coral cornflowerblue cornsilk crimson cyan darkblue darkcyan
      darkgoldenrod darkgray darkgreen darkgrey darkkhaki darkmagenta darkolivegreen darkorange darkorchid darkred
      darksalmon darkseagreen darkslateblue darkslategray darkslategrey darkturquoise darkviolet deeppink deepskyblue
      dimgray dimgrey dodgerblue firebrick floralwhite forestgreen fuchsia gainsboro ghostwhite gold goldenrod gray
      green greenyellow grey honeydew hotpink indianred indigo ivory khaki lavender lavenderblush lawngreen
      lemonchiffon lightblue lightcoral lightcyan lightgoldenrodyellow lightgray lightgreen lightgrey lightpink
      lightsalmon lightseagreen lightskyblue lightslategray lightslategrey lightsteelblue lightyellow lime limegreen
      linen magenta maroon mediumaquamarine mediumblue mediumorchid mediumpurple mediumseagreen mediumslateblue
      mediumspringgreen mediumturquoise mediumvioletred midnightblue mintcream mistyrose moccasin navajowhite navy
      oldlace olive olivedrab orange orangered orchid palegoldenrod palegreen paleturquoise palevioletred papayawhip
      peachpuff peru pink plum powderblue purple rebeccapurple red rosybrown royalblue saddlebrown salmon sandybrown
      seagreen seashell sienna silver skyblue slateblue slategray slategrey snow springgreen steelblue tan teal thistle
      tomato turquoise violet wheat white whitesmoke yellow yellowgreen
    ].freeze

    def self.valid?(value)
      text = value.to_s.downcase
      NAMES.include?(text) || /\A#(?:[0-9a-f]{3,4}|[0-9a-f]{6}|[0-9a-f]{8})\z/.match?(text) ||
        valid_function?(text)
    end

    def self.valid_function?(text)
      if (match = /\Argb\(\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})\s*\)\z/.match(text))
        return match.captures.all? { |channel| channel.to_i <= 255 }
      end
      if (match = /\Ahsl\(\s*(\d{1,3})\s*,\s*(\d{1,3})%\s*,\s*(\d{1,3})%\s*\)\z/.match(text))
        return match[1].to_i <= 360 && match[2].to_i <= 100 && match[3].to_i <= 100
      end
      false
    end
  end
end
