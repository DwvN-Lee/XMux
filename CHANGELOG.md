# Changelog

## 2026-04-28

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
- Added wrapper-first diagnostics through `xmux doctor`, `xmux bridge-status`, `xmux pane-info`, `xmux recover`, and `xmux submit-test`.
- Hardened Copilot teammate operations around TUI submit behavior and Copilot HTTP MCP lifecycle.
