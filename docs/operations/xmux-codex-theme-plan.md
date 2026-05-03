# XMux Codex Terminal Theme Plan

This plan makes the Codex visual theme an XMux-scoped runtime behavior.
Ordinary Ghostty, zsh, and Powerlevel10k configuration must remain unchanged.

## Goal

When a user enters an interactive XMux session, XMux should temporarily switch
the current terminal window to a Codex custom dark palette. When the user exits
or detaches from that XMux session, XMux should restore the terminal to the
user's global defaults.

The theme must be scoped to XMux runtime only:

```text
normal shell
  -> existing Ghostty theme and .p10k.zsh colors

xmux interactive attach/run
  -> temporary Codex custom dark terminal palette

xmux exit or detach
  -> reset to existing Ghostty and .p10k.zsh defaults
```

XMux must not edit these files as part of this feature:

```text
~/.config/ghostty/config
~/.zshrc
~/.p10k.zsh
~/.codex/config.toml
```

## Theme Model

Use terminal OSC color sequences as the primary mechanism. Codex TUI settings
are not sufficient for this goal because Codex `tui.theme` controls syntax
highlighting, not the terminal-wide foreground, background, cursor, and ANSI
palette.

Apply the theme immediately before the user enters the interactive XMux view,
not during detached session creation or non-interactive automation.

Reset the theme immediately after the interactive attach/run returns. The reset
path must run for normal exit, detach, and failed attach attempts that happen
after a theme was applied.

## Palette

The palette is an XMux Codex custom dark override. It must not be documented as
identical to Codex upstream defaults.

Core colors:

```text
background = #0E0F12
foreground = #F5F7FA
cursor     = #10A37F
accent     = #10A37F
muted      = #9EA1AA
```

ANSI palette:

```text
0  = #0E0F12
1  = #FF6B6B
2  = #10A37F
3  = #F2C94C
4  = #4285F4
5  = #8534F3
6  = #2DD4BF
7  = #F5F7FA
8  = #9EA1AA
9  = #FF8A80
10 = #36D399
11 = #FFD166
12 = #6EA8FE
13 = #A371F7
14 = #5EEAD4
15 = #FFFFFF
```

## Runtime Controls

Add or preserve these controls:

```text
XMUX_TERMINAL_THEME=0
  Disable terminal theme injection entirely.

XMUX_TERMINAL_THEME_FORCE=1
  Emit OSC theme sequences even when stdout is not detected as a TTY.
  This is mainly for tests and manual diagnostics.

xmux theme-reset
  Emit terminal reset sequences manually for recovery if a shell or terminal is
  interrupted before automatic reset runs.
```

Default behavior:

```text
xmux interactive attach/run
  Applies the Codex terminal theme unless XMUX_TERMINAL_THEME=0.

xmux detached or non-TTY run
  Does not emit terminal theme sequences.
```

## Implementation Plan

Update the terminal theme helpers in `xmux.zsh` so they provide one shared
lifecycle for interactive XMux lead entry.

Required behavior:

1. Detect whether terminal theme injection is enabled.
2. Emit OSC apply sequences only for an interactive terminal.
3. Wrap interactive attach/run with apply-before and reset-after behavior.
4. Preserve detached and non-TTY behavior without color side effects.
5. Add `xmux theme-reset` as a manual recovery command.

The existing tmux status and pane brand styles should remain separate from the
terminal palette. They can continue to use XMux provider brand colors inside
the tmux session.

## Failure Handling

If reset cannot run because the terminal window, shell, or process is forcefully
terminated, the user's global configuration is still safe because no config file
was changed. The user can recover the current terminal window by running:

```zsh
xmux theme-reset
```

or by opening a new Ghostty window.

## Test Plan

Run static syntax checks:

```zsh
zsh -n xmux.zsh
```

Run focused tests:

```zsh
pytest tests/test_xmux_entrypoint.py
```

Cover these scenarios:

1. Interactive attach emits Codex theme apply sequences before attach.
2. Interactive attach emits reset sequences after attach returns.
3. Detached session creation emits no terminal theme sequences.
4. Non-TTY execution emits no terminal theme sequences by default.
5. `XMUX_TERMINAL_THEME=0` disables theme injection.
6. `XMUX_TERMINAL_THEME_FORCE=1` allows deterministic sequence testing.
7. Existing-tmux lead startup wraps Codex with apply/reset behavior.
8. `xmux theme-reset` emits foreground, background, cursor, and ANSI reset
   sequences.

## Acceptance Criteria

The feature is complete when:

1. `xmux` applies the Codex custom dark palette only while the user is inside
   an interactive XMux session.
2. Exiting or detaching from XMux restores the user's global Ghostty and p10k
   appearance.
3. Global Ghostty, zsh, p10k, and Codex config files are not modified.
4. Detached and automation workflows have no terminal color side effects.
5. Manual reset is available through `xmux theme-reset`.
