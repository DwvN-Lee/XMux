---
name: xmux-codex
description: Explicit XMux trigger for sending a synthesized request from Claude to the Codex peer.
argument-hint: "<routing instruction>"
disable-model-invocation: true
allowed-tools: Bash(xmux claude send-codex:*)
---

<!-- XMUX_MANAGED_CLAUDE_XMUX_CODEX_SKILL -->

# xmux-codex

Explicit XMux trigger for Claude-to-Codex requests.

The user routing instruction is:

```text
$ARGUMENTS
```

Do not forward the routing instruction verbatim unless the user explicitly asks
for literal/raw forwarding. First synthesize a Codex-facing prompt from:

- the current Claude conversation,
- relevant files or evidence already discussed,
- the user routing instruction above,
- the concrete question or task Codex should handle.

Then send only that synthesized Codex-facing prompt through the single XMux
entrypoint:

```zsh
xmux claude send-codex --trigger xmux-codex --title "<short request title>" --prompt "<synthesized Codex-facing prompt>" --quiet
```

After the command succeeds, do not answer the original `/xmux-codex` request
directly. Wait for the Codex response marker:

```text
[xmux-codex-response]
```
