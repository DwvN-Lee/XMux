# XMux

XMux is a Codex-led tmux teammate runtime. The single user-facing command is
`xmux`; Codex is always the lead, and supported teammates are Claude, Gemini,
and Copilot.

Runtime state is project-local:

```text
<project>/.codex/xmux/
  teams/<team>/
    team.json
    inboxes/
    requests/
    events.jsonl
```

Codex uses the normal user runtime under `~/.codex`. XMux does not create an
isolated Codex home for a team, and Codex teammate mode is unsupported.

## Commands

Use the shell-configured entrypoint. In this workspace, `.zshrc` loads the
local `xmux.zsh`; automation should use an interactive zsh when it needs a
fresh shell:

```bash
zsh -ic 'xmux start -n refactor -T refactor-team'
```

Start a Codex lead session:

```bash
xmux start -n refactor -T refactor-team
```

Start with teammates:

```bash
xmux start -n refactor -T refactor-team --claude --gemini --copilot
```

Add or refresh teammates from an existing XMux team:

```bash
xmux claude -t refactor-team
xmux gemini -t refactor-team
xmux copilot -t refactor-team
```

Inspect and operate a team:

```bash
xmux teammates -t refactor-team
xmux doctor -t refactor-team --log-lines 0
xmux bridge-status -t refactor-team
xmux pane-info gemini-worker -t refactor-team
xmux stop -t refactor-team gemini-worker
```

Unsupported legacy paths fail explicitly:

```bash
xmux codex
xmux start --codex
xmux start -c
```

## MCP And Mailbox

The Codex lead MCP server is `xmux_lead`, configured by:

```bash
python3 scripts/setup_xmux_codex_mcp.py --xmux-home "$PWD/.codex/xmux"
```

Provider teammates write responses through `bridge-mcp-server.js`, which uses
`XMUX_HOME`, `XMUX_TEAM`, `XMUX_AGENT`, and `XMUX_OUTBOX`.

## Plugin

The local Codex plugin is `xmux@xmux-local` under `plugins/xmux`. It exposes:

```text
/xmux-teams
/xmux-phase
/xmux-veto
/xmux-claude
/xmux-gemini
/xmux-copilot
/xmux-tools
```

## Docs

- [Codex lead runtime](docs/xmux-codex-lead.md)
- [Wrapper-first debugging](docs/xmux-debugging.md)
- [Gemini teammate](docs/gemini-teammate.md)
- [Copilot teammate](docs/copilot-teammate.md)

## Verification

```bash
pytest tests -q
zsh -n xmux.zsh
zsh -n xmux-bridge.zsh
python3 -m compileall scripts
git diff --check
```
