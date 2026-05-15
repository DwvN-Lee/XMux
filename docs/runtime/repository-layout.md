Back to [README](../../README.md)

# Repository Layout

XMux separates source files by runtime responsibility:

```text
bin/                 public executable wrapper
runtime/             Homebrew-installed XMux terminal runtime
  codex/             Codex TUI pane runner
  claude/            Claude Code TUI pane runner
  shell/             Codex lead shell entrypoint
  prompt/            Claude hook protocol template
  tmux/              tmux runtime configuration
src/                 reusable JavaScript source modules
  claude/            Claude hook harness CLI
  codex/             Codex pane harness CLI and setup helper
dist/                runtime JavaScript entrypoint shims
plugins/xmux/skills/ optional Codex skill source
docs/                user and architecture documentation
```

`XMUX_INSTALL_DIR` always points at the install root. Runtime code must derive
subpaths from that root instead of assuming checkout-relative files.

Distribution boundaries:

- Homebrew installs `bin/`, `runtime/`, `share/`, `src/codex/setup.js`, and the
  Claude/Codex harness shims.
- npm/npx publishes the JavaScript runtime surface used by setup helpers and
  the `xmux-claude-harness` and `xmux-codex-harness` bins.
- GitHub remains the source repository for docs and optional Codex skill source.

The Codex-to-Claude harness path does not depend on MCP, teammate mailboxes, or
pane paste injection. Legacy MCP files are not part of the supported runtime
surface.
