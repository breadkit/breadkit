# breadkit-render

`bkrender` turns a Breadkit DSL or resolved IR JSON file into a standalone SVG diagram. Breadkit DSL input is executable Ruby; only render files you trust. IR JSON is the data-only alternative.

```sh
bkrender circuit.bk.rb -o circuit.svg --show-nets --legend
bkrender circuit.bk.rb -o circuit.png --scale 3 --theme light
bkrender circuit.bk.rb --format svg > circuit.svg
```

## Options

| Option | Default | Description |
| --- | --- | --- |
| `-o, --output PATH` | stdout | Write to a file; `.svg`, `.png`, `.jpg`, and `.jpeg` select the format. |
| `-f, --format FORMAT` | inferred or `svg` | `svg`, `png`, or `jpeg`. Conflicting extensions are errors. |
| `--scale N` | `2` | Raster output scale. |
| `--theme NAME` | `light` | `light`, `dark`, or `print`. |
| `--color-by MODE` | `wire` | Use declared wire colors or deterministic net colors. |
| `--show-nets` | off | Add net labels to the diagram. |
| `--legend` | off | Add the title, net names, and representative wire colors. |
| `--crop MODE` | `auto` | `auto` crops to circuit content; `none` shows the full board. |
| `--annotations FILE` | none | Overlay offenses from `bklint --format json`. |
| `--backend NAME` | `auto` | Raster backend: `rsvg`, `vips`, or `magick`. |
| `--background COLOR` | white | JPEG background: `white`, `black`, `#RGB`, or `#RRGGBB`. |
| `--quality N` | `90` | JPEG quality. |
| `--force` | off | Draw resolved elements even when the input has layout errors. |

## Raster backends

SVG is rendered without extra dependencies. PNG uses the first available backend in the order `rsvg-convert`, `ruby-vips`, ImageMagick. JPEG uses `ruby-vips` or ImageMagick and is flattened onto the configured background. Install `librsvg` (`brew install librsvg` or `apt install librsvg2-bin`) or ImageMagick for raster output. `ruby-vips` also needs a libvips build with SVG support.

The SVG uses a system font stack including Noto Sans JP. Rasterized Japanese labels need a Japanese font installed in the environment.
