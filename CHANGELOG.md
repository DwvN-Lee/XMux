# Changelog

## 1.3.0 - 2026-05-10

- Stabilized the SRP distribution model: Homebrew owns the XMux terminal
  runtime and setup helpers, npm owns MCP lead/bridge/mailbox execution, and
  GitHub owns source, documentation, public skill source, and release artifacts.
- Made Codex setup install-scoped and version-aware: `xmux setup-codex`
  prepares the npm package cache and configures MCP commands to run cached
  package bins directly.
- Hardened `xmux doctor-codex` so it verifies the configured MCP command with
  an initialize probe, confirms mailbox availability, and rejects stale npm
  package caches.
- Added explicit copy-based public skill management through
  `xmux install-skills` and `xmux remove-skills`; skills remain opt-in and are
  not symlinked into Codex.
- Clarified user and architecture docs around the Homebrew, npm, GitHub, and
  skill installation boundaries.

Detailed implementation history before the 1.3.0 distribution baseline is
archived in [Pre-1.3 Changelog](docs/archive/changelog-pre-1.3.md).
