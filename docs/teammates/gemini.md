Back to [README](../../README.md)

# Gemini Teammate

Gemini is an XMux teammate under a Codex lead. Start it only inside an existing
XMux team through the executable XMux entrypoint. For automation, prefer
`xmux <subcommand>` from the installed command or `$XMUX_INSTALL_DIR/bin/xmux`
instead of relying on `.zshrc`:

```bash
xmux teammateAdd -t <team> gemini
```

The bridge reads requests from `<project>/.codex/xmux/teams/<team>/inboxes/`
and Gemini returns responses through the `write_to_lead` MCP tool.
`xmux teammateAdd -t <team> gemini` refreshes `~/.gemini/settings.json` before starting Gemini so the
`xmux_bridge` MCP server points at the installed runtime's
`bridge-mcp-server.js`.

## Setup

Gemini CLI must be installed and authenticated. `xmux teammateAdd` performs runtime
MCP registration automatically. For static stdio registration outside the XMux
wrapper:

```bash
python3 scripts/setup_gemini_mcp.py npx
```

Or point Gemini at a local bridge script:

```bash
python3 scripts/setup_gemini_mcp.py "$PWD/bridge-mcp-server.js"
```

## Model Selection

`xmux teammateAdd -t <team> gemini` does not pin a concrete Gemini model. To
select a model for XMux Gemini panes, set `XMUX_GEMINI_MODEL`; XMux passes it to
Gemini CLI as `GEMINI_MODEL` unless the provider args already include `--model`
or `-m`.

```bash
XMUX_GEMINI_MODEL=default xmux teammateAdd -t <team> gemini  # passes GEMINI_MODEL=auto
XMUX_GEMINI_MODEL=pro xmux teammateAdd -t <team> gemini
XMUX_GEMINI_MODEL=gemini-3.1-pro-preview xmux teammateAdd -t <team> gemini
xmux gemini -t <team> -- --model flash          # explicit CLI arg wins
```

## Operations

```bash
xmux ensure -t <team> gemini-worker --bridge --ready --json
xmux teamStatus -t <team>
xmux teammateStatus -t <team> gemini-worker
xmux pane-info gemini-worker -t <team>
xmux teammateShutdown -t <team> gemini-worker
xmux recover -t <team> gemini-worker --restart-teammate
```

Run `xmux ensure` before sending mailbox pings. It checks the pane, teammate
bridge, Gemini MCP config, mailbox files, and project Gemini instructions file,
then repairs stale scoped state where possible.
