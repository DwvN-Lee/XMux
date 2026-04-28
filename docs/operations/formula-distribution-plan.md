# Homebrew Distribution Worktree Plan

This plan tracks the work to make XMux installable through Homebrew while
preserving `xmux` as the single operational entrypoint.

## Worktree

- Source worktree: `/Users/idongju/Desktop/Git/XMux/.worktrees/formula-dist`
- Branch: `formula-dist`
- Primary user flow: `brew install xmux`, then `xmux -n <session>`

## Goals

- Make Homebrew the stable owner of the XMux runtime files.
- Keep `xmux` as the only user-facing command for tmux/team lifecycle work.
- Ensure global tool config points at a stable Homebrew runtime path, not a
  local checkout, npx cache, or zsh plugin manager cache.
- Keep runtime state project-local under `<project>/.codex/xmux`.
- Do not introduce a required zsh plugin. Install zsh completion only if useful.

## Target Install Layout

```text
<brew-prefix>/bin/xmux
<brew-prefix>/opt/xmux -> <brew-prefix>/Cellar/xmux/<version>
<brew-prefix>/Cellar/xmux/<version>/libexec/
  bin/xmux
  xmux.zsh
  xmux-bridge.zsh
  bridge-mcp-server.js
  xmux-lead-mcp-server.js
  scripts/
  prompt/
  share/zsh/site-functions/_xmux
```

Runtime path responsibilities:

```text
XMUX_INSTALL_DIR = Homebrew libexec path
XMUX_PROJECT_DIR = target project root
XMUX_STATE_DIR   = <project>/.codex/xmux
```

## Implementation Steps

1. Audit runtime file references.
   - Confirm all runtime asset lookups are based on `$XMUX_INSTALL_DIR`.
   - Check `xmux.zsh`, `xmux-bridge.zsh`, `bridge-mcp-server.js`, and
     `xmux-lead-mcp-server.js`.

2. Add a Homebrew formula draft.
   - Suggested repo path: `packaging/homebrew/xmux.rb`.
   - Install runtime files under `libexec`.
   - Write a small `bin/xmux` wrapper that exports `XMUX_INSTALL_DIR=libexec`
     and execs `libexec/bin/xmux`.
   - Declare dependencies on `tmux`, `node`, `python`, and `zsh` as needed.

3. Add a brew-like layout test.
   - Create a temporary `libexec` layout in tests.
   - Run `libexec/bin/xmux --help` with `XMUX_INSTALL_DIR` pointing to that
     temporary layout.
   - Verify project-local state still resolves from the current project, not
     the install directory.

4. Verify explicit Codex setup behavior.
   - `xmux setup-codex` records the Homebrew runtime path as
     `XMUX_INSTALL_DIR`.
   - It does not write global `XMUX_PROJECT_DIR` or `XMUX_STATE_DIR`.
   - Plugin cache wiring is opt-in and not part of Homebrew installation.

5. Add optional zsh completion if practical.
   - Install completion as `share/zsh/site-functions/_xmux`.
   - Do not add a required zsh plugin.

6. Update documentation.
   - Make Homebrew the primary installation path.
   - Document `brew tap`, `brew install`, and `xmux -n <session>`.
   - Move npx/zsh plugin discussion to optional or future notes if retained.

7. Validate locally.
   - `zsh -n xmux.zsh`
   - `zsh -n xmux-bridge.zsh`
   - `python3 -m compileall scripts`
   - `pytest tests -q`
   - Formula install/test manually where Homebrew is available.

## Completion Criteria

- `xmux --help` works from a brew-like install layout without relying on the
  original checkout path.
- Runtime scripts, prompts, and MCP servers are found under `XMUX_INSTALL_DIR`.
- Project state is still created under `<project>/.codex/xmux`.
- Global Codex config stores install-scoped data only after explicit
  `xmux setup-codex`.
- Documentation presents Homebrew as the primary install path.

## Deferred Work

- npx bootstrapper that installs or refreshes the stable runtime.
- Optional zsh plugin for prompt/status integration.
- Homebrew tap repository automation and release checksum update script.
