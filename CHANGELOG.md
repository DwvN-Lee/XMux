# Changelog

## Unreleased

- Replaced public setup commands with the single `xmux setup-xmux`,
  `xmux doctor-xmux`, and `xmux remove-xmux` integration surface.
- Moved Claude hook and `xmux-codex` skill installation to global
  `~/.claude/settings.json` and `~/.claude/skills/xmux-codex`, while keeping
  runtime request state project-local under `.codex/xmux`.
- Added a first-pass `xmux claude ...` hook harness path with project-local
  Claude session, request, prompt, and response state.
- Added split-pane Claude Code TUI transport through `xmux claude pane-run`,
  using a state-scoped Unix socket and PTY writes instead of tmux paste
  commands.
- Reworked the public `xmux-claude` skill to require explicit `$xmux-claude`
  or `$xmux-claude!` triggers and route only through `xmux claude send`.
- Replaced the Claude protocol template with a hook/envelope protocol that does
  not require `write_to_lead`.
- Disabled user-reachable legacy teammate and pane-injection commands in the
  `xmux` dispatcher for this harness path.
- Changed Codex setup to remove legacy `xmux_lead` MCP config and install only
  shell integration, command rules, and the Claude skill surface.
- Documented the Claude harness model and prohibited MCP, teammate, and pane
  paste communication paths for Codex-to-Claude requests.
- Added Claude harness troubleshooting docs for split-pane TUI, socket
  transport, hooks, request state, and recovery.

## 1.3.0 - 2026-05-10

XMux 1.3.0 stabilizes the SRP distribution baseline. Homebrew owns the XMux
terminal runtime and setup helpers, npm owns MCP lead/bridge/mailbox execution,
and GitHub owns source, documentation, public skill source, and release
artifacts.

### New Features

- Added explicit public Codex skill management with `xmux install-skills` and
  `xmux remove-skills`.
- Added copy-based skill installation from Homebrew-installed public skill
  sources under `share/xmux/skills`.
- Added explicit GitHub release skill fetch support through
  `xmux install-skills --from-github --ref <tag>`.

### Improvements

- Made `xmux setup-codex` prepare a versioned npm package cache for MCP
  execution.
- Configured Codex MCP commands to run cached package binaries directly.
- Kept public skills opt-in and copy-installed; XMux does not symlink public
  skills into Codex.
- Clarified the distribution boundary between Homebrew, npm, GitHub, and public
  skills.

### Bug Fixes

- Fixed MCP startup reliability for `xmux_lead` and provider bridges.
- Prevented stale npm package cache reuse by validating the cached
  `xmux-bridge` version against the active XMux release.
- Improved `xmux doctor-codex` so it verifies actual MCP initialize readiness
  instead of only checking configuration text.

### Documentation

- Reworked active release notes around the 1.3.0 distribution baseline.
- Archived pre-1.3 implementation and hotfix history outside the active
  changelog.
- Clarified that public skills are optional copy-installed shortcuts.
- Clarified that runtime operation must not depend on checkout paths.

### Upgrade Notes

After upgrading, run:

```zsh
brew update
brew reinstall dwvn-lee/xmux/xmux
xmux setup-codex
xmux doctor-codex
```

Expected checks:

```text
xmux 1.3.0
[OK] xmux_lead MCP initialize probe succeeded
[OK] mcp package cache: ... (1.3.0)
```

Restart Codex after setup so the MCP client reloads the updated configuration.
