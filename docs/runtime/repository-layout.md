Back to [README](../../README.md)

# Repository Layout

XMux separates source files by runtime responsibility:

```text
bin/                 public executable wrapper
runtime/             Homebrew-installed XMux terminal runtime
  shell/             lead shell entrypoint
  relay/             tmux pane relay
  prompt/            provider protocol templates
  tmux/              tmux runtime configuration
mcp/                 MCP servers and MCP client setup helpers
  servers/           npm/npx MCP entrypoints
  setup/             Codex, Claude, Gemini, and Copilot MCP registration helpers
src/                 reusable JavaScript source modules
dist/                runtime JavaScript entrypoint shims
plugins/xmux/skills/ optional Codex skill source
docs/                user and architecture documentation
```

`XMUX_INSTALL_DIR` always points at the install root. Runtime code must derive
subpaths from that root instead of assuming checkout-relative files.

Distribution boundaries:

- Homebrew installs `bin/`, `runtime/`, `mcp/setup/`, and `share/` as the XMux
  terminal runtime bundle. Public skills are copied into
  `share/xmux/skills/` as read-only source files, not activated in Codex.
- npm/npx publishes the MCP package surface only: `mcp/servers`, `mcp/setup`,
  mailbox runtime files, and reusable JavaScript modules needed by those
  entrypoints.
- GitHub remains the source repository for docs and optional Codex skill
  source. Runtime operation must not require a checkout path.

Runtime code composes those channels: `xmux` comes from Homebrew, while MCP
lead/bridge/mailbox execution resolves through the versioned npm package cache
prepared by `xmux setup-codex`. Runtime operation must not depend on checkout
paths or install-local MCP server paths.
