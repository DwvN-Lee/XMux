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
    codex/pane-run.py
    claude/pane-run.py
    shell/xmux.zsh
    prompt/
    tmux/tmux.conf
  src/
    codex/setup.js
  dist/
    bin/xmux-claude-harness.js
    bin/xmux-codex-harness.js
    claude/
    codex/
  share/xmux/skills/
    xmux-claude/
  share/zsh/site-functions/_xmux
```

The public `$(brew --prefix)/bin/xmux` wrapper exports:

```text
XMUX_INSTALL_DIR=$(brew --prefix)/opt/xmux/libexec
```

Runtime asset lookups for shell, prompt, setup-helper, and Claude/Codex harness
files must derive from `XMUX_INSTALL_DIR`.

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

`xmux setup-codex` owns XMux-managed `~/.codex` changes. In this branch, public
skill installation is limited to `xmux-claude`, and Claude communication is
performed through `xmux claude ...`, Claude Code hooks, and the `xmux codex ...`
return channel.

Activate the optional skill explicitly:

```zsh
xmux install-skills --skill xmux-claude
```

Or opt in during setup:

```zsh
xmux setup-codex --with-skills
```

Remove only XMux-managed Codex integration state with:

```zsh
xmux remove-codex
```

Remove optional skills separately:

```zsh
xmux remove-skills
```
