Back to [README](../../README.md)

# Homebrew Installation

Homebrew is the primary installation path for XMux:

```zsh
brew tap DwvN-Lee/xmux
brew install xmux
xmux setup-xmux
xmux doctor-xmux
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
    xmux/setup.js
    codex/setup.js
  assets/
    claude/skills/xmux-codex/SKILL.md
  dist/
    bin/xmux-claude-harness.js
    bin/xmux-codex-harness.js
    claude/
    codex/
  plugins/xmux/skills/
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

XMux integration is a separate, explicit step:

```zsh
xmux setup-xmux
xmux doctor-xmux
```

`xmux setup-xmux` owns XMux-managed global Codex and Claude changes:
`~/.codex/config.toml`, `~/.codex/rules/default.rules`,
`~/.codex/skills/xmux-claude`, `~/.claude/settings.json`, and
`~/.claude/skills/xmux-codex`. Runtime state remains project-local under
`<project>/.codex/xmux`.

Remove XMux-managed global integration state with:

```zsh
xmux remove-xmux
```

Refresh managed skills and hooks from the installed bundle with:

```zsh
xmux setup-xmux --refresh
```
