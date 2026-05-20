#!/usr/bin/env node
"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), "xmux-claude-context-"));
const fakeBin = path.join(tempRoot, "bin");
fs.mkdirSync(fakeBin, { recursive: true });

const fakeTmux = `#!/usr/bin/env node
"use strict";

const args = process.argv.slice(2);
if (args[0] === "display-message" && args[1] === "-pt") {
  const pane = args[2];
  const format = args.slice(3).join(" ");
  const alive = pane === "%404" || pane === "%405";
  if (format.includes("#{pane_dead}")) {
    console.log(alive ? "0" : "1");
    process.exit(0);
  }
  if (format.includes("#{session_id}") && format.includes("#{window_id}")) {
    if (!alive) process.exit(1);
    console.log("$1\\t@1");
    process.exit(0);
  }
}
console.error("unexpected tmux invocation: " + args.join(" "));
process.exit(1);
`;

const fakeTmuxPath = path.join(fakeBin, "tmux");
fs.writeFileSync(fakeTmuxPath, fakeTmux, "utf8");
fs.chmodSync(fakeTmuxPath, 0o755);

process.env.PATH = `${fakeBin}${path.delimiter}${process.env.PATH || ""}`;
process.env.XMUX_STATE_DIR = tempRoot;
delete process.env.TMUX_PANE;

const codexSessionsDir = path.join(tempRoot, "codex", "sessions");
fs.mkdirSync(codexSessionsDir, { recursive: true });
fs.writeFileSync(path.join(codexSessionsDir, "dev.json"), JSON.stringify({
  schema: "xmux.codex.session.v1",
  name: "dev",
  active: true,
  pane: "%404",
  socket_path: "/tmp/xmux-codex-test-dev.sock",
}, null, 2), "utf8");

const {
  decorateSessionRuntime,
  resolveCodexPaneContext,
} = require("../src/claude/cli");

process.env.XMUX_CODEX_SESSION_NAME = "dev";
assert.deepEqual(resolveCodexPaneContext(tempRoot), {
  sessionName: "dev",
  pane: "%404",
  referencePane: "%404",
  referencePaneSource: "codex-session-state",
});

delete process.env.XMUX_CODEX_SESSION_NAME;
assert.deepEqual(resolveCodexPaneContext(tempRoot), {
  sessionName: "dev",
  pane: "%404",
  referencePane: "%404",
  referencePaneSource: "codex-session-state",
});

fs.writeFileSync(path.join(codexSessionsDir, "other.json"), JSON.stringify({
  schema: "xmux.codex.session.v1",
  name: "other",
  active: true,
  pane: "%405",
}, null, 2), "utf8");
assert.equal(resolveCodexPaneContext(tempRoot).reason, "ambiguous_codex_session_without_tmux_context");

const stale = decorateSessionRuntime({
  schema: "xmux.claude.session.v1",
  name: "dev",
  active: true,
  transport_backend: "pane",
  pane: "%401",
  socket_path: path.join(tempRoot, "missing.sock"),
});
assert.equal(stale.active, false);
assert.equal(stale.recorded_active, true);
assert.equal(stale.runtime_status, "stale");
assert.deepEqual(stale.stale_reasons.sort(), ["pane_not_alive", "socket_missing"]);

const inactive = decorateSessionRuntime({
  schema: "xmux.claude.session.v1",
  name: "stopped",
  active: false,
  transport_backend: "pane",
});
assert.equal(inactive.active, false);
assert.equal(inactive.runtime_status, "inactive");

fs.rmSync(tempRoot, { recursive: true, force: true });

console.log("claude pane context tests passed");
