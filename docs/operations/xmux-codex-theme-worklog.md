# XMux Codex Theme Worklog

This document records the work completed so far for the XMux-scoped Codex
terminal theme effort.

## Worktree State

The Codex theme work was moved out of the main worktree into a dedicated
worktree:

```text
path:   .worktree/codex-theme
branch: codex-theme
base:   main at c1d2f78
```

The main worktree was restored to its pre-theme-change state for the files that
belong to this effort.

Main still has unrelated pre-existing dirty files:

```text
scripts/setup_xmux_codex_mcp.py
tests/test_xmux_setup_mcp.py
.codex/config.toml
CLAUDE.md
```

Those files are not part of this theme work.

## Files Changed In This Worktree

```text
xmux.zsh
share/zsh/site-functions/_xmux
tests/test_xmux_entrypoint.py
docs/operations/xmux-codex-theme-plan.md
docs/operations/xmux-codex-theme-worklog.md
```

## Completed Changes

Moved the Codex terminal theme from a preview-only path to normal interactive
XMux lead entry.

Added terminal OSC helpers in `xmux.zsh`:

```text
_xmux_terminal_theme_can_emit
_xmux_terminal_osc
_xmux_apply_terminal_codex_theme
_xmux_reset_terminal_theme
_xmux_terminal_theme_enabled
_xmux_with_terminal_codex_theme
_xmux_attach_session
```

The apply helper currently emits a Codex custom dark palette:

```text
foreground = #F5F7FA
background = #0E0F12
cursor     = #10A37F
```

It also sets ANSI palette entries used by the XMux Codex dark theme.

Theme application now wraps both interactive lead entry paths:

```text
outside tmux:
  apply terminal theme
  tmux attach-session
  reset terminal theme

inside tmux:
  apply terminal theme
  run Codex lead
  reset terminal theme
```

This avoids changing the terminal during detached/non-TTY session creation.

Removed the temporary preview command path and its preview-only environment
flag.

Added a manual recovery command:

```text
xmux theme-reset
```

Added a runtime escape hatch:

```text
XMUX_TERMINAL_THEME=0
```

Added a planning document:

```text
docs/operations/xmux-codex-theme-plan.md
```

That document records the intended final behavior: apply the custom Codex dark
theme during interactive XMux usage only, then restore the user's global
Ghostty and p10k appearance after exit or detach.

## Tests Added

Added coverage in `tests/test_xmux_entrypoint.py` for:

```text
terminal Codex theme OSC sequences
theme reset OSC sequences
non-TTY/detached mode without theme side effects
attach wrapper apply/reset behavior
inside-tmux lead run apply/reset behavior
XMUX_TERMINAL_THEME=0 disable behavior
xmux theme-reset behavior
```

The focused test suite was rerun after enabling normal interactive `xmux`
theme activation:

```text
zsh -n xmux.zsh
pytest tests/test_xmux_entrypoint.py
```

Observed result at that point:

```text
92 passed
```

## Next Implementation Step

Manually verify in Ghostty with a normal `xmux` command:

```zsh
cd /Users/idongju/Desktop/Git/XMux/.worktree/codex-theme
bin/xmux -T codex-theme -n codex-theme-preview
```

Implementation should follow:

```text
docs/operations/xmux-codex-theme-plan.md
```

and should preserve the main rule:

```text
Do not modify Ghostty config, .zshrc, .p10k.zsh, or global Codex config.
```
