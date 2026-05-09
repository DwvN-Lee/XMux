Back to [README](../../README.md)

# Claude Teammate

Claude is an XMux teammate under a Codex lead. Start it only inside an existing
XMux team through the executable XMux entrypoint. For automation, prefer
`xmux <subcommand>` from the installed command or `$XMUX_INSTALL_DIR/bin/xmux`
instead of relying on `.zshrc`:

```bash
xmux teammateAdd -t <team> claude
```

Claude uses a local-scope Claude Code MCP server named `xmux_bridge`.
`xmux teammateAdd -t <team> claude` updates the current project's entry in
`~/.claude.json` before starting Claude so `write_to_lead` can write responses
back to the Codex lead inbox.

XMux also installs a managed protocol block into the project `CLAUDE.md`. If the
file already exists, existing project instructions are preserved outside the
XMux protocol markers.

## Setup

Claude Code must be installed and authenticated. `xmux teammateAdd` performs
runtime MCP registration automatically.

Manual registration is for development or troubleshooting only:

```bash
node mcp/setup/claude.js \
  "$PWD/mcp/servers/bridge.js" \
  "$PWD" \
  "$PWD/.codex/xmux/teams/<team>/inboxes/codex-lead.json" \
  claude-worker \
  <team> \
  "$PWD/.codex/xmux" \
  "$PWD"
```

## Operations

```bash
xmux ensure -t <team> claude-worker --bridge --ready --json
xmux teamStatus -t <team>
xmux teammateStatus -t <team> claude-worker
xmux paneInfo claude-worker -t <team>
xmux teammateShutdown -t <team> claude-worker
xmux recover -t <team> claude-worker --restart-teammate
```

Run `xmux ensure` before sending mailbox pings. It checks the pane, teammate
bridge, Claude MCP config, mailbox files, and project Claude instructions file,
then repairs stale scoped state where possible.
