# XMux Claude Harness Protocol

This project may install XMux Claude hooks for Codex-to-Claude requests.

## Mode Detection

Treat source-based bracket markers as XMux transport messages:

```text
[xmux-codex-request]

<Claude-facing prompt>
```

The visible body is the actual prompt Codex sent to Claude. XMux keeps request
IDs, nonces, and hashes out of the visible prompt; they live in project-local
metadata and pane-run memory. The XMux hook validates the active request before
marking it accepted and verifies the visible prompt body against the volatile
in-memory body. If validation fails, do not attempt XMux delivery.

`/xmux-codex` is reserved as a user trigger for Claude-originated requests to
Codex. Treat its arguments as routing and synthesis instructions, not as the
final Codex-facing payload. Synthesize a Codex-facing prompt from the current
Claude conversation and the user's routing instruction, then send only that
synthesized prompt with:

```zsh
xmux claude send-codex --trigger xmux-codex --title "<short request title>" --prompt "<synthesized Codex-facing prompt>" --quiet
```

It is not a Codex-to-Claude request marker, and it must not be forwarded
verbatim unless the user explicitly requests literal/raw forwarding.

## Response Delivery

Do not call MCP tools for XMux. There is no `write_to_lead` requirement in the
hook harness.

When an XMux request is active, complete the task normally. The XMux `Stop` hook
records response metadata only when the request was accepted through
`[xmux-codex-request]`, and when the Codex pane harness is active, delivers a
verified response marker into the Codex TUI:

```text
[xmux-claude-response]

<Claude response body>
```

Codex validates the pending response metadata internally and then processes the
clean `[xmux-claude-response]` prompt. XMux does not persist the response body by
default.

## Rules

1. Do not invent or call `write_to_lead`.
2. Do not expose request nonces or internal state unless asked for debugging.
3. Answer only the visible `[xmux-codex-request]` request body and relevant context.
4. If `/xmux-codex` is invoked, synthesize before sending; do not pass the routing text through literally by default.
5. If the command is invalid, do not send anything to Codex.
