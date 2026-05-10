Back to [README](../../README.md)

# Codex Skills

XMux Codex skills are optional shortcuts. They are not required for the XMux
runtime, MCP lead server, provider bridge, or mailbox to work.

Public skills are maintained in the repository under:

```text
plugins/xmux/skills/
```

Homebrew installs the public skill source as read-only files under:

```text
<XMUX_INSTALL_DIR>/share/xmux/skills/
```

Activate the optional shortcuts explicitly:

```zsh
xmux install-skills
```

Or configure Codex and activate the shortcuts in one explicit setup command:

```zsh
xmux setup-codex --with-skills
```

This copies XMux-managed public skills into the active Codex home:

```text
~/.codex/skills/
```

The installer copies only public skills:

```text
xmux-teams
xmux-claude
xmux-gemini
xmux-copilot
xmux-diagnosis
xmux-send-pane
```

`xmux-phase` and `xmux-veto` are local-only workflows and are not installed by
the public skill installer.

Use a specific local source when developing or testing:

```zsh
xmux install-skills --skills-dir /path/to/plugins/xmux/skills
```

Install selected skills only:

```zsh
xmux install-skills --skill xmux-teams --skill xmux-claude
```

Refresh XMux-managed skills:

```zsh
xmux install-skills --refresh
```

Remove only XMux-managed skills:

```zsh
xmux remove-skills
```

`xmux remove-codex` leaves skills in place by default. Use
`xmux remove-codex --with-skills` when removing the Codex integration and
XMux-managed skills together.

The installer does not overwrite a user-created skill with the same name unless
the destination is marked as XMux-managed and `--force` or `--refresh` is used.
Each copied skill contains `.xmux-managed-skill`, and the skills directory also
records `.xmux-skills.json` metadata for troubleshooting.

Network fetch is explicit. Use it only when the local Homebrew source is not
available:

```zsh
xmux install-skills --from-github --ref v1.2.2
```
