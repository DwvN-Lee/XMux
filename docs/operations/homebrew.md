Back to [README](../../README.md)

# Homebrew Installation

Homebrew is the primary installation path for XMux:

```zsh
brew tap DwvN-Lee/xmux
brew install xmux
xmux setup-codex
xmux doctor-codex
xmux -n refactor
```

The Formula installs runtime files under Homebrew `libexec`:

```text
$(brew --prefix)/opt/xmux/libexec/
  bin/xmux
  runtime/
    shell/xmux.zsh
    relay/xmux-bridge.zsh
    prompt/
    tmux/tmux.conf
  mcp/
    setup/
  share/zsh/site-functions/_xmux
```

The Formula installs the terminal runtime and the small setup helpers needed to
connect provider CLIs to that runtime. MCP server and mailbox execution are
resolved from the versioned npm package.

The public `$(brew --prefix)/bin/xmux` wrapper exports:

```text
XMUX_INSTALL_DIR=$(brew --prefix)/opt/xmux/libexec
```

It then execs `libexec/bin/xmux`. Runtime asset lookups for shell, relay,
prompt, and setup-helper files must derive from `XMUX_INSTALL_DIR`.

Project state remains separate from the install:

```text
XMUX_PROJECT_DIR=<project root>
XMUX_STATE_DIR=<project root>/.codex/xmux
```

Codex integration is a separate, explicit step:

```zsh
xmux setup-codex
xmux doctor-codex
```

`xmux setup-codex` owns `~/.codex` changes. It records `XMUX_INSTALL_DIR`, the
installed `bin` path, and a versioned npm `xmux_lead` MCP entrypoint; installs
a scoped XMux command rule; and prepares the npm package cache used by MCP
mailbox helpers. Homebrew remains the terminal runtime source through
`XMUX_INSTALL_DIR`. Setup must not write `XMUX_PROJECT_DIR` or
`XMUX_STATE_DIR`, because those are inherited from the active
`xmux -n <session>` runtime.

Remove only XMux-managed Codex integration state with:

```zsh
xmux remove-codex
```
