# frozen_string_literal: true

# Set these four environment variables from the actual underside contacts and
# breadboard holes. The catalog deliberately has no guessed mounting spacing.
board :full

part :PS1, :shillehtek_mb102_4pin,
     pins: {
       LEFT_POS: ENV.fetch("MB102_LEFT_POS"),
       LEFT_GND: ENV.fetch("MB102_LEFT_GND"),
       RIGHT_POS: ENV.fetch("MB102_RIGHT_POS"),
       RIGHT_GND: ENV.fetch("MB102_RIGHT_GND")
     },
     master: :on, left: :v3_3, right: :v5
