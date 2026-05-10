#!/usr/bin/env node
"use strict";

const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const SERVER_NAME = "xmux_bridge";
const LEGACY_NAMES = new Set([
  "xmux_bridge",
  "xmux-bridge",
  "clau_mux_bridge",
  "clau-mux-bridge",
  "amux_bridge",
  "amux-bridge",
]);
const DEFAULT_NPX_PREFIX = path.join(os.homedir(), ".cache", "xmux", "npm-prefix");

function stableHomebrewXmuxFilePath(inputPath) {
  const resolved = path.resolve(inputPath.replace(/^~(?=$|\/)/, os.homedir()));
  const marker = `${path.sep}Cellar${path.sep}xmux${path.sep}`;
  const libexecSegment = `${path.sep}libexec${path.sep}`;
  const libexecIndex = resolved.indexOf(libexecSegment);
  if (!resolved.includes(marker) || libexecIndex < 0) return resolved;
  const prefix = resolved.split(marker, 1)[0];
  const optDir = path.join(prefix, "opt", "xmux", "libexec");
  const relativePath = resolved.slice(libexecIndex + libexecSegment.length);
  const candidate = path.join(optDir, relativePath);
  if ((fs.existsSync(path.join(optDir, "runtime", "shell", "xmux.zsh")) || fs.existsSync(path.join(optDir, "xmux.zsh"))) && fs.existsSync(candidate)) {
    return candidate;
  }
  return resolved;
}

function main(argv = process.argv.slice(2)) {
  const cmd = argv[0] ?? "npx";
  const settingsPath = path.join(os.homedir(), ".gemini", "settings.json");

  let settings = {};
  if (fs.existsSync(settingsPath)) {
    settings = JSON.parse(fs.readFileSync(settingsPath, "utf-8"));
    if (settings === null || Array.isArray(settings) || typeof settings !== "object") {
      settings = {};
    }
  }

  const servers = settings.mcpServers ?? {};
  if (servers === null || Array.isArray(servers) || typeof servers !== "object") {
    throw new Error("error: ~/.gemini/settings.json mcpServers must be a JSON object");
  }
  settings.mcpServers = servers;

  for (const legacyName of LEGACY_NAMES) {
    delete servers[legacyName];
  }

  if (cmd === "npx") {
    const npxPrefix = process.env.XMUX_MCP_NPX_PREFIX || DEFAULT_NPX_PREFIX;
    servers[SERVER_NAME] = {
      command: "npx",
      args: ["--prefix", npxPrefix, "xmux-bridge"],
      trust: true,
    };
  } else {
    servers[SERVER_NAME] = {
      command: "node",
      args: [stableHomebrewXmuxFilePath(cmd)],
      trust: true,
    };
  }

  fs.mkdirSync(path.dirname(settingsPath), { recursive: true });
  fs.writeFileSync(settingsPath, `${JSON.stringify(settings, null, 2)}\n`, "utf-8");
  return 0;
}

if (require.main === module) {
  try {
    process.exitCode = main();
  } catch (error) {
    process.stderr.write(`${String(error.message || error)}\n`);
    process.exitCode = 1;
  }
}

module.exports = {
  main,
  stableHomebrewXmuxFilePath,
};
