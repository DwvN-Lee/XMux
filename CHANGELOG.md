# Changelog

## 2026-05-06

- Reworked XMux Codex skills around their operational scope: multi-teammate
  cross review, single-provider teammate review, direct pane injection, and
  diagnostics are now separated into focused skills.
- Renamed `$xmux-tools` to `$xmux-diagnosis` and updated the plugin skill source,
  mirrored skill distribution, docs, and skill exposure tests.
- Narrowed `$xmux-send-pane` to active XMux lead/session or explicit pane prompt
  injection instead of team-oriented teammate routing.

## 2026-05-04

- Released 1.0.36 with stable Homebrew `opt/xmux/libexec` targeting for Codex,
  Claude, Gemini, and Copilot MCP configuration so future upgrades do not leave
  MCP clients pinned to stale Cellar version paths.
- Released 1.0.35 with an XMux-scoped Codex custom dark terminal theme that
  applies during interactive XMux runtime and resets on detach or exit.
- Added `xmux theme-reset`, `XMUX_TERMINAL_THEME=0`, zsh completion support for
  the reset command, and tests for interactive theme apply/reset behavior.
- Fixed `xmux doctor-codex` so already installed managed XMux skills are
  accepted without requiring a local skill source directory.

## 2026-05-03

- Released 1.0.34 with Codex/OpenAI-branded XMux pane borders and session
  status bar styling, provider-colored teammate pane names, and a runtime
  opt-out through `XMUX_STATUS_STYLE=0`.

## 2026-05-02

- Released 1.0.33 with Claude teammate MCP callback registration, a managed
  Claude team protocol block, dash-style Codex skill names, `xmux-send-pane`,
  and stale Codex MCP process diagnostics.

## 2026-04-29

- Released 1.0.32 with the 1.0.31 `xmux --version` support plus post-upgrade
  fixes for XMux skill YAML frontmatter, stale Homebrew Cellar PATH cleanup,
  and MCP test environment isolation.
- Released 1.0.31 with `xmux --version` and `xmux -V` support.

## 2026-04-28

- Prepared the 1.0.3 command-surface cleanup by removing duplicate aliases
  while hiding agent and debug commands from the default user help.
- Added split help topics: `xmux help agent`, `xmux help debug`, and
  `xmux help all`.
- Replaced the low-level pane prompt injection entrypoint with
  `xmux sendPane`.
- Improved the XMux Codex lead workflow so users can start with `xmux -n <session>`
  and let the agent manage teammates, status checks, and shutdown.
- Made the `xmux` command available to Codex-managed workflows, reducing the need
  for long internal wrapper paths during normal team operations.
- Refined team lifecycle behavior so teammate shutdown and full team shutdown
  have clearer roles, with completed teams archived after shutdown.

## 2026-04-27

- Fixed teammate shutdown behavior so stopping teammates keeps or restores focus
  on the lead pane instead of exposing helper shutdown output.
- Split XMux runtime path environment names into install, project, and state
  directories.

## 2026-04-26

- Documented the XMux Codex lead runtime, local Codex plugin, and MCP/mailbox teammate model.
- Added wrapper-first diagnostics through `xmux doctor`, `xmux bridgeStatus`,
  `xmux paneInfo`, and `xmux recover`.
- Hardened Copilot teammate operations around TUI submit behavior and Copilot HTTP MCP lifecycle.
