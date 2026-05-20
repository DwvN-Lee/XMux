#!/usr/bin/env node
"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const {
  codexPluginHookDiagnostics,
  removeXmuxCodexHooksFromConfig,
} = require("../src/codex/setup");

const config = {
  hooks: {
    PreToolUse: [
      {
        matcher: "Bash|Shell",
        hooks: [
          {
            type: "command",
            command: "/Users/example/.agents/plugins/personal-guardrails/hooks/shell-risk-gate.sh",
          },
        ],
      },
    ],
    Stop: [
      {
        hooks: [
          {
            type: "command",
            command: "python3 /Users/example/.codex/hooks/ax_retrospective_stop.py",
          },
          {
            type: "command",
            command: "XMUX_HOOK_TAG='xmux-codex-harness' XMUX_INSTALL_DIR='/opt/homebrew/opt/xmux/libexec' '/opt/homebrew/opt/xmux/libexec/bin/xmux' codex hook stop",
          },
        ],
      },
    ],
    UserPromptSubmit: [
      {
        hooks: [
          {
            type: "command",
            command: "XMUX_HOOK_TAG='xmux-codex-harness' XMUX_INSTALL_DIR='/opt/homebrew/opt/xmux/libexec' '/opt/homebrew/opt/xmux/libexec/bin/xmux' codex hook user-prompt",
          },
        ],
      },
    ],
  },
};

assert.equal(removeXmuxCodexHooksFromConfig(config), 2, "only XMux-managed hooks are removed");
assert.deepEqual(Object.keys(config.hooks).sort(), ["PreToolUse", "Stop"], "events with non-XMux hooks remain");
assert.equal(config.hooks.PreToolUse[0].hooks[0].command.endsWith("shell-risk-gate.sh"), true);
assert.equal(config.hooks.Stop[0].hooks[0].command.endsWith("ax_retrospective_stop.py"), true);

const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), "xmux-codex-hooks-"));
const configPath = path.join(tempRoot, "config.toml");
const globalHooksPath = path.join(tempRoot, "hooks.json");
const pluginHooksPath = path.join(
  tempRoot,
  "plugins",
  "cache",
  "idongju-local",
  "personal-guardrails",
  "0.2.0",
  "hooks.json",
);

fs.writeFileSync(configPath, "", "utf8");
fs.mkdirSync(path.dirname(pluginHooksPath), { recursive: true });
fs.writeFileSync(globalHooksPath, JSON.stringify({
  hooks: {
    PreToolUse: [
      {
        matcher: "Bash|Shell",
        hooks: [
          {
            type: "command",
            command: "/Users/example/.agents/plugins/personal-guardrails/hooks/shell-risk-gate.sh",
          },
        ],
      },
    ],
  },
}, null, 2), "utf8");
fs.writeFileSync(pluginHooksPath, JSON.stringify({
  hooks: {
    PreToolUse: [
      {
        matcher: "Bash|Shell",
        hooks: [
          {
            type: "command",
            command: "./hooks/shell-risk-gate.sh",
          },
        ],
      },
    ],
  },
}, null, 2), "utf8");

const warnings = codexPluginHookDiagnostics(configPath);
assert.equal(warnings.some((warning) => warning.includes("relative command") && warning.includes("./hooks/shell-risk-gate.sh")), true);
assert.equal(warnings.some((warning) => warning.includes("both global hooks and plugin cache") && warning.includes("shell-risk-gate.sh")), true);

fs.rmSync(tempRoot, { recursive: true, force: true });

console.log("codex setup hook tests passed");
