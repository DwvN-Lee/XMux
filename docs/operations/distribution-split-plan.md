# Distribution Responsibility Split Plan

This plan separates XMux distribution into two independent responsibilities:

1. Homebrew installs the terminal runtime.
2. Explicit `.codex` setup installs Codex integration assets.

The main rule is that Homebrew must not own Codex global configuration, skills,
or legacy plugin cache state.

## Responsibility Model

```text
Homebrew
  Owns: XMux CLI/runtime files.
  Does not own: ~/.codex config, skills, plugins, rules.

.codex setup
  Owns: Codex MCP config, skills, optional plugin metadata, rules.
  Does not own: Homebrew install paths or package manager lifecycle.
```

## Homebrew Scope

Homebrew should install only the runtime required for terminal operation:

```text
bin/xmux
xmux.zsh
xmux-bridge.zsh
bridge-mcp-server.js
xmux-lead-mcp-server.js
scripts/
prompt/
share/zsh/site-functions/_xmux
```

Homebrew must not install these as runtime-owned assets:

```text
plugins/xmux/**
skills/**
Codex plugin command files
Codex skill files
Legacy Codex plugin cache files
```

The installed wrapper should still export:

```text
XMUX_INSTALL_DIR=<homebrew libexec>
```

`XMUX_PROJECT_DIR` and `XMUX_STATE_DIR` remain derived from the target project
at runtime.

## `.codex` Setup Scope

Codex integration should happen only through an explicit user command, such as:

```text
xmux setup-codex
xmux setup-codex --skills-dir /path/to/xmux-skills
xmux doctor-codex
xmux remove-codex
```

`xmux setup-codex` should handle:

```text
~/.codex/config.toml xmux_lead MCP registration
~/.codex/config.toml shell PATH/XMUX_INSTALL_DIR values
~/.codex/rules/default.rules scoped xmux allow rule
~/.codex/skills/xmux-* skill install or refresh from --skills-dir
  or XMUX_CODEX_SKILLS_DIR
optional Codex plugin metadata if still needed
```

The command must be explicit because it mutates user-global Codex state.

## Required Changes

1. Narrow the Homebrew Formula.
   - Remove `libexec.install "plugins"`.
   - Do not install `skills/`.
   - Keep runtime files, scripts, prompts, and zsh completion.
   - Update Formula test if it assumes plugin files exist.

2. Split `scripts/setup_xmux_codex_mcp.py`.
   - Default behavior should configure MCP/PATH/rules only when called by the
     explicit Codex setup flow.
   - Plugin/cache installation must be opt-in or moved to a separate script.
   - It must never run as a side effect of Homebrew installation.

3. Update `xmux.zsh` command surface.
   - Add an explicit setup command, for example `xmux setup-codex`.
   - Add diagnostics/removal commands if practical:
     `xmux doctor-codex`, `xmux remove-codex`.
   - Avoid hidden `.codex` mutations during ordinary `xmux --help`,
     `xmux teamStatus`, or non-lead diagnostic commands.

4. Revisit `_xmux_prepare_codex_runtime`.
   - Decide whether `xmux -n <session>` may auto-prepare MCP only, or whether
     all `.codex` mutations require prior `xmux setup-codex`.
   - Preferred direction: ordinary runtime should validate and warn when Codex
     integration is missing; explicit setup command performs mutation.

5. Install skills into `.codex`, not Homebrew.
   - Source assets may remain in the repo for development, but setup must use
     an explicit source path.
   - Distribution/install target should be `~/.codex/skills/xmux-*`.
   - Document how skills are refreshed and removed.

6. Update documentation.
   - README: Homebrew installs runtime only.
   - Homebrew docs: no Codex skills/plugin ownership.
   - Codex runtime docs: `.codex` setup is explicit and separate.
   - Debugging docs: clarify which command owns which state.

7. Update tests.
   - Homebrew layout test must pass without `plugins/`.
   - Codex setup tests should prove:
     - explicit setup writes expected config blocks;
     - default runtime removes stale legacy plugin cache and does not install it;
     - skills install path is under `.codex/skills`;
     - remove command deletes only XMux-managed blocks/assets.

## Proposed User Flows

Runtime install:

```zsh
brew tap DvwN-Lee/xmux
brew install xmux
xmux --help
```

Codex integration:

```zsh
xmux setup-codex
xmux doctor-codex
```

Use:

```zsh
cd <project>
xmux -n refactor
```

Removal:

```zsh
xmux remove-codex
brew uninstall xmux
```

## Completion Criteria

- Homebrew Formula does not install `plugins/` or `skills/`.
- `brew` layout still supports `xmux --help` and runtime shell scripts.
- `.codex` global state changes occur only through explicit setup/remove
  commands.
- Codex skills are installed to `.codex/skills`, not loaded from Homebrew.
- `plugins/xmux/skills` remains the canonical skill source; top-level `skills/`
  remains a mirrored distribution copy.
- Documentation presents Homebrew and `.codex` setup as separate steps.
- Tests cover both responsibilities independently.
