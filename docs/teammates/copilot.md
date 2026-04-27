Back to [README](../../README.md)

# Copilot Teammate

Copilot is an XMux teammate under a Codex lead. Start it only inside an existing
XMux team from a shell that already loads the XMux wrapper. For automation, use
an interactive zsh so `.zshrc` provides `xmux`:

```bash
zsh -ic 'xmux copilot -t <team>'
```

Copilot uses the bridge MCP server in HTTP/SSE mode. `xmux copilot` allocates a
local port, starts `bridge-mcp-server.js --http`, and updates
`~/.copilot/mcp-config.json`.

## Setup

Copilot CLI must be installed and authenticated. For static stdio registration
in clients that support it:

```bash
python3 scripts/setup_copilot_mcp.py npx
```

Runtime Copilot panes normally use the dynamic HTTP/SSE registration performed
by `xmux copilot`.

## Operations

```bash
xmux ensure -t <team> copilot-worker --bridge --ready --json
xmux teammates -t <team>
xmux bridge-status -t <team> copilot-worker
xmux pane-info copilot-worker -t <team>
xmux stop -t <team> copilot-worker
xmux recover -t <team> copilot-worker --restart-teammate
```

Run `xmux ensure` before sending mailbox pings. It checks the pane, teammate
bridge, Copilot HTTP MCP pid, dynamic SSE config, mailbox files, and project
Copilot instructions file, then repairs stale scoped state where possible.
