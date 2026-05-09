Back to [README](../../README.md)

# Copilot Teammate

Copilot is an XMux teammate under a Codex lead. Start it only inside an existing
XMux team through the executable XMux entrypoint. For automation, prefer
`xmux <subcommand>` from the installed command or `$XMUX_INSTALL_DIR/bin/xmux`
instead of relying on `.zshrc`:

```bash
xmux teammateAdd -t <team> copilot
```

Copilot uses the bridge MCP server in HTTP/SSE mode. `xmux teammateAdd` allocates
a local port, starts `mcp/servers/bridge.js --http`, and updates
`~/.copilot/mcp-config.json`.

## Setup

Copilot CLI must be installed and authenticated. Runtime Copilot panes normally
use the dynamic HTTP/SSE registration performed by `xmux teammateAdd`.

Manual static stdio registration is for clients that support it and for
development or troubleshooting:

```bash
node mcp/setup/copilot.js npx
```

## Operations

```bash
xmux ensure -t <team> copilot-worker --bridge --ready --json
xmux teamStatus -t <team>
xmux teammateStatus -t <team> copilot-worker
xmux paneInfo copilot-worker -t <team>
xmux teammateShutdown -t <team> copilot-worker
xmux recover -t <team> copilot-worker --restart-teammate
```

Run `xmux ensure` before sending mailbox pings. It checks the pane, teammate
bridge, Copilot HTTP MCP pid, dynamic SSE config, mailbox files, and project
Copilot instructions file, then repairs stale scoped state where possible.
