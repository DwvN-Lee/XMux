#!/usr/bin/env node
"use strict";

const assert = require("node:assert/strict");
const {
  isXmuxOwnedBinPath,
  pathWithXmuxBin,
  removeCodexShellEnvironment,
} = require("../src/codex/setup");

const installDir = "/opt/homebrew/opt/xmux/libexec";
const installBin = `${installDir}/bin`;
const staleBetaCellar = "/opt/homebrew/Cellar/xmux-beta/2.0.2-beta.6/libexec/bin";
const staleBetaOpt = "/opt/homebrew/opt/xmux-beta/libexec/bin";
const staleStableCellar = "/opt/homebrew/Cellar/xmux/2.0.1/libexec/bin";
const nodeCellar = "/opt/homebrew/Cellar/node/26.0.0/bin";
const homebrewBin = "/opt/homebrew/bin";
const localBin = "/Users/example/.local/bin";

assert.equal(isXmuxOwnedBinPath(staleBetaCellar, installBin), true, "stale beta Cellar path is XMux-owned");
assert.equal(isXmuxOwnedBinPath(staleBetaOpt, installBin), true, "stale beta opt path is XMux-owned");
assert.equal(isXmuxOwnedBinPath(staleStableCellar, installBin), true, "stale stable Cellar path is XMux-owned");
assert.equal(isXmuxOwnedBinPath(homebrewBin, installBin), false, "Homebrew bin is not XMux-owned");
assert.equal(isXmuxOwnedBinPath(nodeCellar, installBin), false, "non-XMux Cellar path is not XMux-owned");
assert.equal(isXmuxOwnedBinPath(localBin, installBin), false, "user local bin is not XMux-owned");

const mixedPath = [
  staleBetaCellar,
  nodeCellar,
  staleBetaOpt,
  localBin,
  staleStableCellar,
  homebrewBin,
].join(":");

assert.equal(
  pathWithXmuxBin(installDir, mixedPath),
  [installBin, nodeCellar, localBin, homebrewBin].join(":"),
  "pathWithXmuxBin strips only XMux-owned entries and preserves order",
);

const config = [
  "[shell_environment_policy.set]",
  `PATH = "${mixedPath}"`,
  `XMUX_INSTALL_DIR = "${installDir}"`,
  'TMPDIR = "/tmp"',
  "",
].join("\n");

assert.equal(
  removeCodexShellEnvironment(config, installDir),
  [
    "[shell_environment_policy.set]",
    `PATH = "${nodeCellar}:${localBin}:${homebrewBin}"`,
    'TMPDIR = "/tmp"',
    "",
  ].join("\n"),
  "removeCodexShellEnvironment applies the same XMux-owned filter",
);

console.log("codex setup PATH tests passed");
