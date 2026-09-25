# breadkit-lint

`bklint` checks Breadkit DSL and IR files for layout, electrical, and wiring-intent problems. DSL files execute as Ruby code; inspect only trusted files. Use IR JSON for data-only input. Configuration `require` entries also execute Ruby code, so load only trusted configuration files.

```sh
bklint examples/01_led_button.bk.rb
bklint circuit.bk.rb --only Electrical/ShortCircuit
bklint circuit.bk.rb --format json --out lint.json
bklint circuit.bk.rb --format github
bklint circuit.bk.rb --format sarif --out lint.sarif
```

## Options

`bklint [options] [FILES...]` accepts `.bk.rb` and `.json` inputs. With no files, it scans visible `**/*.bk.rb` files under the current directory.

| Option | Description |
| --- | --- |
| `-f, --format FORMAT` | `text` (default), `json`, `github`, or `sarif`. |
| `-o, --out PATH` | Write formatter output to a file. |
| `-c, --config PATH` | Load a `.bklint.yml` configuration. |
| `--fail-level LEVEL` | `error`, `warning` (default), or `info`. |
| `--only RULES` / `--except RULES` | Select or skip comma-separated rule IDs. |
| `--switch-states MODE` | Evaluate `none`, `single` (default), or `all` switch states. |
| `--list-rules` | List registered rules. |
| `--explain RULE` | Show rule guidance and an example. |
| `--locale LOCALE` | `ja` or `en` for rule descriptions and text summary. |

Exit status is `0` when no offense meets the fail level, `1` when one does, and `2` for invalid input, configuration, or command usage.

## Configuration

```yaml
inherit_from:
  - ./shared/bklint.yml
use_parts:
  - ./parts/*.yml

Electrical/FloatingPin:
  Severity: error

Style/WireColor:
  Enabled: true
  PositiveColors: [red, orange]
  GroundColors: [black, blue]
```

All built-in rules and defaults are in [`config/default.yml`](config/default.yml). `.bklint.yml` can also set `AllRules.SwitchStates`, `AllRules.FailLevel`, `AllRules.Exclude`, and `require` custom rule files. DSL `lint_disable` declarations suppress a rule globally or for one named target.

Use `bklint --format json` with `bkrender --annotations` to display offense markers on a diagram. Rule guidance is in [`docs/rules`](docs/rules).
