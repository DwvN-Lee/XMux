Back to [README](../../README.md)

# XMux Skills

XMux installs only the protocol assets required for the Codex-Claude hook
harness. Skills are not a separate public install surface in 2.0.0.

Run the single integration command:

```zsh
xmux setup-xmux
```

This installs XMux-managed global assets:

```text
~/.agents/skills/xmux-claude/
~/.claude/skills/xmux-codex/
```

The Codex skill is sourced from the installed bundle:

```text
<XMUX_INSTALL_DIR>/assets/codex/skills/xmux-claude/
```

The Claude skill is sourced from:

```text
<XMUX_INSTALL_DIR>/assets/claude/skills/xmux-codex/SKILL.md
```

Both destinations are protected by `.xmux-managed-skill` marker files. Setup
refuses to overwrite a user-created asset with the same name unless the
destination is already marked as XMux-managed.

Refresh managed assets:

```zsh
xmux setup-xmux --refresh
```

Preview changes without writing:

```zsh
xmux setup-xmux --dry-run
```

Remove XMux-managed global assets:

```zsh
xmux remove-xmux
```

Legacy XMux 1.x skill and Codex agent-proxy locations are not refreshed by
`setup-xmux`. Review and remove them separately:

```zsh
xmux cleanup-legacy --dry-run
xmux cleanup-legacy
```

This cleanup removes only XMux-managed legacy assets, such as the old
`~/.codex/skills/xmux-claude/` install, `.xmux-skills.json`, legacy
`~/.codex/agents/xmux_*.toml` proxy roles with `# XMUX_MANAGED_AGENT`, and
obsolete `.agents/skills/xmux-*` provider symlinks. Non-XMux skills, agents,
and plugin registries are left untouched.

Runtime request and response state is never stored globally. It stays under the
active project:

```text
<project>/.codex/xmux/
```
