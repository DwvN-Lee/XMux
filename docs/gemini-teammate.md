← [README](../README.md)

# Gemini Teammate

Gemini is an XMux teammate under a Codex lead. Start it only inside an existing
XMux team from a shell that already loads the XMux wrapper. For automation, use
an interactive zsh so `.zshrc` provides `xmux`:

```bash
zsh -ic 'xmux gemini -t <team>'
```

The bridge reads requests from `<project>/.codex/xmux/teams/<team>/inboxes/`
and Gemini returns responses through the `write_to_lead` MCP tool.

## Setup

Gemini CLI must be installed and authenticated. Register the bridge MCP server:

```bash
python3 scripts/setup_gemini_mcp.py npx
```

Or point Gemini at a local bridge script:

```bash
python3 scripts/setup_gemini_mcp.py "$PWD/bridge-mcp-server.js"
```

## Operations

```bash
xmux teammates -t <team>
xmux bridge-status -t <team> gemini-worker
xmux pane-info gemini-worker -t <team>
xmux stop -t <team> gemini-worker
xmux recover -t <team> gemini-worker --restart-teammate
```
