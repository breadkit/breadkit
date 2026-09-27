# Compatibility and versioning

Breadkit, breadkit-lint, and breadkit-render are separate gems. Each gem has its
own version and release schedule. The lint and render gemspecs declare the core
versions they support; no shared release number is required.

Breadkit is currently a 0.x project. Until 1.0, a minor release may change the
Ruby DSL, CLI, or analysis behavior. Patch releases preserve their documented
inputs and output contracts. After 1.0, incompatible DSL or Ruby API changes
require a new major gem version.

JSON interfaces have their own `schema_version`, independent of gem versions:

| Interface | Current schema | Compatibility rule |
| --- | --- | --- |
| Circuit IR | [v1](https://breadkit.github.io/breadkit/schema/ir-v1.json) for one unnamed board; [v2](https://breadkit.github.io/breadkit/schema/ir-v2.json) for named boards | A reader accepts supported versions explicitly. A breaking field or meaning change requires a new schema version. |
| Part YAML | [v1](https://breadkit.github.io/breadkit/schema/part-v1.json) | New optional fields may be added. Existing fields keep their meaning within v1. |
| Board YAML | [v1](https://breadkit.github.io/breadkit/schema/board-v1.json) | New optional fields may be added. Existing fields keep their meaning within v1. |

The JSON IR writer selects v1 for a single unnamed board and v2 for named
boards. Consumers should check `schema_version` before reading an IR file and
ignore unknown optional fields. They should not infer the IR version from the
gem version. The linter publishes its own [result schema](https://breadkit.github.io/breadkit-lint/schemas/lint-v1.json).

Before a 1.0 release, changes to a public schema or documented DSL form need
round-trip coverage and an entry in the relevant gem's changelog. The published
schema files are versioned artifacts; changing a v1 schema to reinterpret
existing fields is a breaking change and requires v2 instead.
