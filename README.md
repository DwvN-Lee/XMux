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
brew tap DwvN-Lee/xmux
brew install xmux
```

Configure Codex integration explicitly:

```bash
xmux setup-codex
xmux doctor-codex
```

`xmux setup-codex` registers XMux with Codex, and `xmux doctor-codex` checks
that the integration is ready.

Start the Codex lead from the target project directory:

```bash
xmux -n refactor
```

XMux displays short names with the project prefix, such as `XMux/refactor`.
Raw `tmux ls` may show a slash-free internal session key; use `xmux sessions`
and `xmux attach XMux/refactor` for user-facing runtime operations.

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
XMUX_INSTALL_DIR  # XMux install root
XMUX_PROJECT_DIR  # project root where Codex is working
XMUX_STATE_DIR    # project-local runtime state, usually $XMUX_PROJECT_DIR/.codex/xmux
```

Codex uses the normal user runtime under `~/.codex`. XMux does not create an
isolated Codex home for a team, and Codex teammate mode is unsupported.

Agent automation uses the installed `xmux` command that `xmux setup-codex`
makes available to Codex. The user-facing bootstrap command remains
`xmux -n <session>` after setup.

The Codex lead MCP server is `xmux_lead`. `xmux setup-codex` configures it so
Codex can route requests, wait for teammate responses, read events, and inspect
team status.
The installed `xmux` command owns the tmux runtime. The `xmux_lead` MCP server
is delivered as a versioned npm entrypoint, and Codex skills are optional
shortcuts for orchestrating that runtime. The MCP command is install-scoped and
does not pin `XMUX_PROJECT_DIR`/`XMUX_STATE_DIR`; those values come from the
active `xmux -n <session>` lead runtime.

Provider teammates write responses through the versioned npm `xmux-bridge`
entrypoint, using the team runtime environment prepared by XMux. MCP and
mailbox paths are implementation details behind Codex-led teammate
orchestration.

Users can ask for teammate work in natural language. When XMux skills are
available in Codex, the official skill shortcuts are:

```text
$xmux-teams
$xmux-claude
$xmux-gemini
$xmux-copilot
$xmux-diagnosis
$xmux-send-pane
```

Homebrew installation details live in [Homebrew installation](docs/operations/homebrew.md).

## Docs

- [Documentation index](docs/README.md)
- [Repository layout](docs/runtime/repository-layout.md)
- [Codex lead runtime](docs/runtime/codex-lead.md)
- [Homebrew installation](docs/operations/homebrew.md)
- [Wrapper-first debugging](docs/operations/debugging.md)
- [Claude teammate](docs/teammates/claude.md)
- [Gemini teammate](docs/teammates/gemini.md)
- [Copilot teammate](docs/teammates/copilot.md)
