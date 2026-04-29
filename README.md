# XMux

XMux is a Codex-led tmux teammate runtime. The single user-facing command is
`xmux`; Codex is always the lead, and supported teammates are Claude, Gemini,
and Copilot.

<table>
  <tr>
    <th>Create</th>
    <th>Shutdown</th>
  </tr>
  <tr>
    <td><img src="docs/screenshots/team-create.png" alt="XMux team creation" width="100%"></td>
    <td><img src="docs/screenshots/team-shutdown.png" alt="XMux team shutdown" width="100%"></td>
  </tr>
</table>

## How to Use

Install XMux with Homebrew:

```bash
brew tap DvwN-Lee/xmux
brew install xmux
```

Homebrew owns the stable runtime under `$(brew --prefix)/opt/xmux/libexec`.
The installed `xmux` command exports that path as `XMUX_INSTALL_DIR` and then
execs the runtime wrapper in `libexec/bin/xmux`. Ad hoc local directories, npx
caches, and zsh plugin directories are not part of the normal runtime path.

Configure Codex integration explicitly:

```bash
xmux setup-codex
xmux doctor-codex
```

Homebrew installs the XMux CLI/runtime only. `xmux setup-codex` is the command
that mutates `~/.codex`: it registers the `xmux_lead` MCP server, adds the
installed `xmux` path to Codex shell policy, installs the scoped XMux command
rule, and refreshes available XMux skills under `~/.codex/skills`. Runtime-only
installs do not include skill source files, so pass an external skill source
when refreshing skills:

```bash
xmux setup-codex --skills-dir /path/to/xmux-skills
```

`XMUX_CODEX_SKILLS_DIR` provides the same source path for automation. Without
`--skills-dir` or `XMUX_CODEX_SKILLS_DIR`, `setup-codex` skips skill refresh
and leaves existing user-owned skills untouched.

Start the Codex lead from the target project directory:

```bash
xmux -n refactor
```

This is the only command users normally need to run directly. After the lead is
open, ask Codex for teammate work in natural language. For example:

- "Use Gemini and Copilot to review this change."
- "Ask Claude to look for edge cases before implementation."
- "Ask Copilot for a repository-aware implementation check."

Codex then manages the XMux lifecycle through hidden agent-facing commands such as:

```bash
xmux teamStatus
xmux teammateAdd -t refactor claude gemini copilot
xmux teammateShutdown -t refactor gemini-worker
xmux teamShutdown -t refactor --reason manual-shutdown
```

Those commands are hidden from the default `xmux --help` output. Use
`xmux help agent` when agent-facing lifecycle syntax is needed for automation
or troubleshooting.

To start a detached or scripted team outside an interactive lead session, Codex
automation can use:

```bash
xmux teamCreate -t refactor-team -n refactor claude gemini copilot
```

XMux is agent friendly: when the user explicitly asks to use teammates, the
Codex lead may create the scoped team, attach requested teammates, send mailbox
requests, wait for responses, and perform bounded retries without asking the
user to approve each XMux step. Runtime permission prompts are only for the
tooling boundary, such as tmux access from a sandboxed process.

Inspect and operate a team when debugging:

```bash
xmux teamStatus -t refactor
xmux doctor -t refactor --log-lines 0
xmux teammateStatus -t refactor
xmux paneInfo gemini-worker -t refactor
xmux teammateShutdown -t refactor gemini-worker
xmux teamShutdown -t refactor --reason manual-shutdown
```

Lower-level diagnostics are also hidden from the default help. Use
`xmux help debug` for the full troubleshooting surface.

`xmux teammateShutdown` keeps the team live. `xmux teamShutdown` is team-wide
and archives the team state while preserving inboxes, requests, request ids,
and events. Lead `/exit` triggers shutdown/archive by default; start with
`--keep-team-on-lead-exit` to leave teammates running for debugging.

Unsupported legacy paths fail explicitly because Codex is the XMux lead, not a
teammate:

```bash
xmux codex
xmux start --codex
xmux start -c
```

## Agent-Managed Internals

This section describes the runtime work handled by Codex and XMux automation.
Users normally do not run these steps directly.

Runtime state is project-local:

```text
<project>/.codex/xmux/
  teams/<team>/
    team.json
    inboxes/
    requests/
    events.jsonl
  archive/<timestamp>-<team>/
    archive.json
    team.json
    inboxes/
    requests/
    events.jsonl
```

Runtime path environment names are now split by responsibility:

```text
XMUX_INSTALL_DIR  # XMux source/install directory
XMUX_PROJECT_DIR  # project root where Codex is working
XMUX_STATE_DIR    # project-local runtime state, usually $XMUX_PROJECT_DIR/.codex/xmux
```

Codex uses the normal user runtime under `~/.codex`. XMux does not create an
isolated Codex home for a team, and Codex teammate mode is unsupported.

Agent automation uses `xmux` from the Codex shell policy PATH that
`xmux setup-codex` writes to `~/.codex/config.toml`. If that wrapper is
unavailable, it falls back to the explicit XMux executable. The user-facing
bootstrap command remains `xmux -n <session>` after setup; ad hoc local paths
and shell-loading details are not part of the agent contract.

The Codex lead MCP server is `xmux_lead`. `xmux setup-codex` configures it so
Codex can route requests, wait for teammate responses, read events, and inspect
team status.
The global MCP config is install-scoped and does not pin
`XMUX_PROJECT_DIR`/`XMUX_STATE_DIR`; those values come from the active
`xmux -n <session>` lead runtime.

Provider teammates write responses through `bridge-mcp-server.js`, using the
team runtime environment prepared by XMux. The bridge and mailbox paths are
implementation details behind Codex-led teammate orchestration.

The explicit Codex setup installs available XMux skills under
`~/.codex/skills` only from `--skills-dir` or `XMUX_CODEX_SKILLS_DIR`.
Homebrew does not install Codex skills or repo-local plugin files; normal
runtime operation depends on the installed `xmux` command and
`XMUX_INSTALL_DIR`, not a checkout path.

The plugin skill source of truth is `plugins/xmux/skills`; the top-level
`skills/` directory is a mirrored distribution copy for explicit skill refresh
workflows. Users explicitly invoke Codex skills with `$`, for example
`$xmux-teams`. The official XMux skills cover agent-facing orchestration flows:

```text
$xmux-teams
$xmux-claude
$xmux-gemini
$xmux-copilot
$xmux-tools
```

Development verification for agent/runtime changes:

```bash
pytest tests -q
zsh -n xmux.zsh
zsh -n xmux-bridge.zsh
python3 -m compileall scripts
git diff --check
```

Formula draft and distribution notes live in
[Homebrew distribution](docs/operations/homebrew.md).

## Docs

- [Documentation index](docs/README.md)
- [Codex lead runtime](docs/runtime/codex-lead.md)
- [Homebrew distribution](docs/operations/homebrew.md)
- [Wrapper-first debugging](docs/operations/debugging.md)
- [Gemini teammate](docs/teammates/gemini.md)
- [Copilot teammate](docs/teammates/copilot.md)
