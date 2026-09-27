# MCP server

`breadkit-mcp` exposes read-only circuit inspection over the Model Context
Protocol (MCP) stdio transport. It uses the [official Ruby MCP SDK](https://ruby.sdk.modelcontextprotocol.io/server/transports/).

Start the server from a project directory:

```sh
breadkit-mcp
```

The current directory is the file root. Set it explicitly when your MCP client
starts the server elsewhere:

```sh
breadkit-mcp --root /absolute/path/to/project
```

A client configuration that accepts `command` and `args` can use:

```json
{
  "command": "breadkit-mcp",
  "args": ["--root", "/absolute/path/to/project"]
}
```

The server offers three tools:

| Tool | Input | Result |
| --- | --- | --- |
| `breadkit_resolve` | `path` | Board and component summary, validity, and diagnostics. |
| `breadkit_nets` | `path`, optional `state` | Electrical nets, members, holes, and constrained potentials. Use `state: "base"` for the default switch state. |
| `breadkit_ir` | `path` | The resolved JSON IR. Requires a circuit without error diagnostics. |

All project paths must remain inside the configured root, including symlink
targets and referenced part or board definition files. Accepted circuit inputs are
`.bk.yml`, `.bk.yaml`, `.bk.toml`, and `.json` IR. Ruby DSL files are not
evaluated by this server. Tool failures return MCP `isError` results, and
standard output contains only protocol messages.

See the [MCP tools specification](https://modelcontextprotocol.io/specification/2025-11-25/server/tools)
for the tool protocol and the [stdio transport specification](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/stdio)
for message framing.
