<p align="center">
  <img src="site/favicon.svg" width="72" height="72" alt="">
</p>

<h1 align="center">breadkit</h1>

<p align="center">
  <strong>Describe breadboard circuits in Ruby. See how every connection fits together.</strong>
</p>

<p align="center">
  <a href="https://rubygems.org/gems/breadkit"><img src="https://img.shields.io/gem/v/breadkit.svg" alt="RubyGems version"></a>
  <a href="https://github.com/breadkit/breadkit/actions/workflows/ci.yml"><img src="https://github.com/breadkit/breadkit/actions/workflows/ci.yml/badge.svg" alt="CI status"></a>
  <img src="https://img.shields.io/badge/Ruby-%3E%3D%203.3-CC342D.svg" alt="Ruby 3.3 or newer">
  <a href="LICENSE.txt"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT license"></a>
</p>

<p align="center">
  <a href="#quick-start">Quick start</a> ·
  <a href="#what-breadkit-provides">Features</a> ·
  <a href="#documentation">Documentation</a> ·
  <a href="#development">Development</a> ·
  <a href="https://breadkit.github.io/breadkit/">Website</a>
</p>

---

Breadkit is the core of a three-gem toolkit for breadboard circuits. It turns a
Ruby description of boards, components, and wires into resolved connections and
JSON IR. [breadkit-render](https://github.com/breadkit/breadkit-render) draws the
circuit; [breadkit-lint](https://github.com/breadkit/breadkit-lint) checks it.

<p align="center">
  <img src="site/assets/01_led_button.svg" width="240" alt="Half-size breadboard diagram with a button, resistor, and LED">
</p>

<p align="center"><sub>A circuit described with Breadkit and drawn with breadkit-render.</sub></p>

## Quick start

Install the gem with Ruby 3.3 or newer:

```sh
gem install breadkit
```

Save this as `circuit.bk.rb`:

```ruby
title "Button and LED"
board :half

supply :USB, voltage: 5.0, plus: "B+1", minus: "B-1"
net :VCC, at: "B+1"
net :GND, at: "B-1"

button :SW1, at: "e10"
resistor :R1, "330", pins: %w[a12 a16]
led :D1, color: :red, anode: "b16", cathode: "b17"

wire "a10", "B+", color: :red
wire "a17", "B-", color: :black
```

Inspect the connected nets or export the circuit for other tools:

```sh
breadkit nets circuit.bk.rb
breadkit ir circuit.bk.rb > circuit.json
breadkit parts
```

The [complete button and LED example](examples/01_led_button.bk.rb) also
declares the connections it expects.

## What Breadkit provides

| Capability | What it does |
| --- | --- |
| Ruby DSL | Place boards, parts, supplies, wires, and connection expectations. |
| Board and part definitions | Start with full, half, and mini boards or load your own YAML definitions. |
| Connectivity analysis | Resolve conductive strips, pins, and switch states into named nets. |
| JSON IR | Pass resolved circuits to the renderer, linter, or another tool. |

The renderer creates SVG, PNG, and JPEG diagrams. The linter reports layout,
electrical, and wiring-intent problems. Each gem is released separately.

## Documentation

- [User guide](https://breadkit.github.io/breadkit/guide/) — write a circuit and see its output.
- [Component catalog](https://breadkit.github.io/breadkit/guide/components/) — boards, built-in parts, and custom modules.
- [DSL reference](https://breadkit.github.io/breadkit/guide/dsl/) — methods, pins, nets, and custom definitions.
- [Project design](docs/DESIGN.md) — the data model and resolution rules.

DSL files execute Ruby code. Load only files you trust; use JSON IR when the
input must be data-only.

## Development

```sh
git clone https://github.com/breadkit/breadkit.git
cd breadkit
bundle install
bundle exec rake
```

## License

Breadkit is available under the [MIT License](LICENSE.txt).
