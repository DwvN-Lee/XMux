Back to project [README](../../../README.md)

# 2026-04-27 Runtime Hotfix Notes

Internal implementation record for the April 27 XMux runtime hotfix.

## User-Facing Issue

Stopping teammates could briefly expose a tmux helper command page instead of
keeping the user on the Codex lead pane. The helper page could show a command
ending in `bridge-mcp-server.js --http <port>` followed by `returned 143`.

The final runtime state was clean. The defect was the shutdown experience: the
lead pane focus was not stable while helper processes were being terminated.

## Root Cause

Copilot's HTTP MCP helper runs under `tmux run-shell -b` and waits for a
background Node process:

```sh
node bridge-mcp-server.js --http <port> ... &
printf '%s\n' "$!" > <pid-file>
wait "$!"
```

During `xmux stop`, XMux sends SIGTERM to the helper process. Shell `wait`
returns `143`, which is the expected SIGTERM status. tmux treats that non-zero
helper exit as a command failure and can surface the helper command output to
the attached user.

## Fix

- `xmux stop` now selects the current pane or Codex lead pane before killing
  teammate/helper processes and restores focus again after the teammate pane is
  killed.
- Helper commands now normalize expected SIGTERM shutdown:

```sh
wait "$!"; rc=$?; case "$rc" in 0|143) exit 0 ;; *) exit "$rc" ;; esac
```

- PID shutdown waits briefly for helper processes to exit before removing pid
  files, reducing races where tmux can show stale helper output.

## Related Gemini Runtime Work

The same hotfix batch also addressed Gemini callback readiness:

- `xmux gemini` refreshes `~/.gemini/settings.json` at pane startup so
  `xmux_bridge` points at the repo-local `bridge-mcp-server.js`.
- `scripts/setup_gemini_mcp.py` removes legacy bridge names before writing the
  canonical `xmux_bridge` entry.
- `XMUX_GEMINI_MODEL` is opt-in. `default` maps to `GEMINI_MODEL=auto`; `pro`
  and concrete Gemini CLI model ids are passed through without hardcoding a
  moving Gemini model version in XMux.
- Explicit Gemini CLI model args (`--model`, `--model=...`, `-m`, `-m=...`)
  take precedence over `XMUX_GEMINI_MODEL`.

## Verification

Automated checks:

```bash
zsh -n xmux.zsh
zsh -n xmux-bridge.zsh
git diff --check
python3 -m pytest
```

Result:

```text
73 passed, 1 skipped
```

Manual checks:

- `demo:gemini-worker` restarted with `XMUX_GEMINI_MODEL=default`.
- Gemini `/mcp status` showed `xmux_bridge - Ready (1 tool)`.
- Mailbox ping `ping-gemini-20260427-03` completed through `write_to_lead` with
  text `pong from gemini env model`.

## Operational Note

Existing helpers that were already started with the old `wait "$!"` command can
still show one final `returned 143` when stopped. New or recovered teammates
created after sourcing the patched `xmux.zsh` use the normalized helper command.

To confirm the patched wrapper is active:

```zsh
print -r -- "$XMUX_DIR"
typeset -f _xmux_start_copilot_mcp | grep '143'
```
