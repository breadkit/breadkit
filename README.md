# Breadkit

Breadkit describes breadboard circuits in Ruby, resolves physical hole connections, checks wiring, and renders diagrams. Ruby 3.3 or newer is required.

| Gem | Command | Purpose |
| --- | --- | --- |
| `breadkit` | `breadkit` | DSL, board and part definitions, connectivity analysis, JSON IR |
| `breadkit-render` | `bkrender` | SVG, PNG, and JPEG diagrams |
| `breadkit-lint` | `bklint` | Layout, electrical, and wiring-intent checks |

The renderer and linter install `breadkit` as a dependency.

## Quick start

```sh
gem install breadkit-render breadkit-lint
bklint examples/01_led_button.bk.rb
bkrender examples/01_led_button.bk.rb -o /tmp/led.svg --show-nets --legend
```

![Rendered button and LED circuit](docs/assets/01_led_button.svg)

See the [DSL reference](docs/dsl.md), [renderer guide](breadkit-render/README.md), and [linter guide](breadkit-lint/README.md).

DSL files execute as Ruby code. Only load trusted files; use IR JSON when input must remain data-only.

## Development

```sh
bundle install
bundle exec rake
bundle exec rake build
```

The raster backends are optional. Install `librsvg` or ImageMagick for PNG and JPEG output. See the [work procedure](docs/WORK_PROCEDURE.md) for CI, release, and hardware verification steps.
