Back to [README](../../README.md)

# Homebrew Distribution

Homebrew is the primary installation path for XMux:

```zsh
brew tap DvwN-Lee/xmux
brew install xmux
xmux setup-codex
xmux doctor-codex
xmux -n refactor
```

The Formula installs runtime files under Homebrew `libexec`:

```text
$(brew --prefix)/opt/xmux/libexec/
  bin/xmux
  xmux.zsh
  xmux-bridge.zsh
  bridge-mcp-server.js
  xmux-lead-mcp-server.js
  scripts/
  prompt/
  share/zsh/site-functions/_xmux
```

The Formula intentionally does not install `plugins/`, top-level `skills/`, or
Codex slash-command files into Homebrew `libexec`. Homebrew owns only the
terminal runtime.

The public `$(brew --prefix)/bin/xmux` wrapper exports:

```text
XMUX_INSTALL_DIR=$(brew --prefix)/opt/xmux/libexec
```

It then execs `libexec/bin/xmux`. Runtime asset lookups for scripts, prompts,
and MCP servers must derive from `XMUX_INSTALL_DIR`.

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
installed `bin` path, and the `xmux_lead` MCP server path; installs a scoped
XMux command rule; and refreshes available XMux skills under
`~/.codex/skills`. It must not write global `XMUX_PROJECT_DIR` or
`XMUX_STATE_DIR`, because those are inherited from the active
`xmux -n <session>` runtime.

Runtime-only package installs do not include Codex skill source files. Provide
an external source directory when skill refresh is needed:

```zsh
xmux setup-codex --skills-dir /path/to/xmux-skills
```

`XMUX_CODEX_SKILLS_DIR` provides the same source path for automation. Without
an explicit skill source, `setup-codex` skips skill refresh. It does not infer
skills from a local checkout path.

Remove only XMux-managed Codex integration state with:

```zsh
xmux remove-codex
```

The Formula source is stored at `packaging/homebrew/xmux.rb`; publish the same
Formula content to the tap repository for external installation.
