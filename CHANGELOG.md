# Changelog

## 0.1.0 — 2026-09-25

### breadkit

- Added the breadboard DSL, built-in boards and parts, pin and wire resolution, connectivity and potential analysis, switch states, and JSON IR.
- Added `breadkit nets`, `breadkit parts`, and `breadkit ir`.

### breadkit-render

- Added deterministic SVG rendering and optional PNG/JPEG output through installed rasterizer backends.
- Added wire/net colors, themes, cropping, legends, and `bklint` annotations.

### breadkit-lint

- Added layout, electrical, and intent rules with text, JSON, GitHub annotation, and SARIF output.
- Added configurable severities, rule selection, exclusions, suppressions, and custom rule loading.
