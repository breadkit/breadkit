# Locking local definitions

Circuit files can load local YAML part and board definitions with `use_parts`
and `use_boards`. Patterns may match different files after a project changes.
Run `breadkit lock FILE` to record the exact matched paths and their SHA-256
checksums:

```yaml
# logger.bk.yml
board: mini
use_parts: [parts/*.yml]
offboard:
  - {ref: SENSOR, type: custom_sensor}
```

```sh
breadkit lock logger.bk.yml
breadkit nets logger.bk.yml
```

The command writes `breadkit.lock` beside the circuit. Commit the lockfile
with the circuit and definitions. Each entry records a circuit filename, the
Breadkit version, and relative paths and checksums for its local part and
board YAML files. Multiple circuit files in one directory have separate
entries in the same lockfile. Running `breadkit lock FILE` again updates only
that circuit's entry.

When a lockfile exists, Breadkit checks the entry before resolving a Ruby,
YAML, or TOML circuit. A changed definition, a new or removed glob match, a
different Breadkit version, or a missing circuit entry stops loading with an
error. Run `breadkit lock FILE` again after intentionally changing local
definitions. This check also applies to the MCP and LSP servers when they
resolve supported circuit inputs. JSON IR files are self-contained and do not
use the lockfile.

The lockfile pins only local YAML definitions loaded by `use_parts` and
`use_boards`, plus the Breadkit version. It does not hash the circuit source,
Ruby DSL files loaded with `include`, other gems, or external tools. Ruby DSL
files are executable and should only be loaded when trusted. Declarative YAML
and TOML circuit files remain data-only.

## Vendored part packs

To share a versioned pack today, keep its YAML files under your project, for
example as a Git submodule pinned to a commit under `vendor/parts/`. Point
`use_parts` at those local files and commit both the Git revision and
`breadkit.lock`. The lock checks the exact YAML bytes even if a submodule or
checkout changes unexpectedly:

```yaml
board: mini
use_parts: [vendor/parts/*.yml]
```

Breadkit does not download packs, resolve remote versions, or authenticate a
Git source. Those steps remain with your existing Git or package manager
workflow. Avoid loading unpinned remote files directly into a circuit.

For a shared Git pack, pin the submodule to a reviewed commit and commit the
submodule pointer, circuit, and generated lockfile together. In CI, check out
submodules before running Breadkit. A pack repository can validate each
definition with `breadkit check-part`; editors can use the public
[`part-v1` schema](https://breadkit.github.io/breadkit/schema/part-v1.json):

```sh
for file in parts/*.yml; do
  breadkit check-part "$file"
done
```

Consumers should run `breadkit nets FILE` or `breadkit ir FILE` in CI after
the submodule checkout. That verifies the recorded SHA-256 bytes and the
exact set of matched definitions before a diagram or report is produced.
The Git commit pins the pack version; `breadkit.lock` catches changed YAML
bytes or newly matched files even when the checkout differs from that commit.
