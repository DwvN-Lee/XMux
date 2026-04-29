# Changelog

## 2026-04-29

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
