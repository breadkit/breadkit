# Language server and VS Code extension

`breadkit-lsp` is a stdio Language Server Protocol 3.18 server. It provides:

- Full-document diagnostics as a YAML or TOML circuit is edited.
- Completion for board holes, rail holes, component pins, and net labels.
- Hover with the resolved net name and potential. Unconstrained potentials are
  shown as unknown.

The server accepts `.bk.yml`, `.bk.yaml`, `.bk.toml`, and `.bk.rb` documents.
YAML and TOML buffers use safe data parsers and do not execute Ruby. Ruby DSL
files receive hole completion without evaluation by default. To enable full
Ruby diagnostics, component pin completion, and net hover, start the server
with both `--root DIRECTORY` and `--trusted-ruby`. This evaluates Ruby source,
including unsaved edits, with the permissions of the server process. Use it
only for code you trust. `--root` limits data-only circuit files and declared
part or board files to that directory. It is not a sandbox for Ruby code.

```sh
breadkit-lsp --root /path/to/project
```

The server uses standard LSP framing on stdin/stdout. It supports `initialize`,
`shutdown`, `exit`, full `didOpen`/`didChange`/`didClose` synchronization,
`textDocument/completion`, `textDocument/hover`, and push diagnostics. Run it
from an LSP client; stdout is reserved for protocol messages.

## VS Code

The source for the minimal desktop extension is in [`vscode/`](../vscode/).
It needs VS Code 1.100 or newer and the `breadkit` gem installed in the Ruby
environment used by VS Code. Preview also needs the separately installed
`breadkit-render` gem (`bkrender` command).

To make a local VSIX with the [VS Code extension packaging tool](https://code.visualstudio.com/api/working-with-extensions/publishing-extension):

```sh
cd vscode
vsce package
code --install-extension breadkit-0.1.0.vsix
```

Open a `.bk.yml`, `.bk.yaml`, `.bk.toml`, or `.bk.rb` file. The extension starts
the server when a Breadkit file is opened. Run **Breadkit: Preview Circuit**
from the Command Palette to render the saved file as a static, dark SVG in a
side panel. Save edits before previewing. Preview runs only in a trusted
workspace. For Ruby files, set `breadkit.evaluateRubyDsl` to `true` as well.
The setting also enables Ruby analysis after the extension host restarts.

Set `breadkit.serverCommand` or `breadkit.renderCommand` if the commands are
not on VS Code's `PATH`. The extension uses direct process execution without
a shell. With one workspace folder, it passes that folder as `--root`. In a
multi-folder window, data-only files work but Ruby evaluation remains disabled.

Diagnostics from declarative files currently point to the first line of the
file because the shared data loader does not preserve field locations.
Completion is prefix-based; source with a parse error may have fewer
suggestions. Hover reports resolved supply potential only and does not imply
current or a simulated operating point.
