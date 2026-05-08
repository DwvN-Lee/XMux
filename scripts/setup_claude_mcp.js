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

function absolute(inputPath) {
  return path.resolve(inputPath.replace(/^~(?=$|\/)/, os.homedir()));
}

function stableHomebrewXmuxInstallDir(installDir) {
  const resolved = absolute(installDir);
  const marker = `${path.sep}Cellar${path.sep}xmux${path.sep}`;
  if (!resolved.includes(marker) || !resolved.endsWith(`${path.sep}libexec`)) {
    return resolved;
  }

  const prefix = resolved.split(marker, 1)[0];
  const candidate = path.join(prefix, "opt", "xmux", "libexec");
  if (fs.existsSync(path.join(candidate, "xmux.zsh"))) {
    return candidate;
  }
  return resolved;
}

function stableHomebrewXmuxFilePath(filePath) {
  const resolved = absolute(filePath);
  const installDir = path.dirname(resolved);
  const stableInstallDir = stableHomebrewXmuxInstallDir(installDir);
  if (stableInstallDir === installDir) {
    return resolved;
  }

  const candidate = path.join(stableInstallDir, path.basename(resolved));
  if (fs.existsSync(candidate)) {
    return candidate;
  }
  return resolved;
}

function loadJson(filePath) {
  if (!fs.existsSync(filePath)) {
    return {};
  }
  const parsed = JSON.parse(fs.readFileSync(filePath, "utf-8"));
  if (parsed === null || Array.isArray(parsed) || typeof parsed !== "object") {
    throw new Error(`error: ${filePath} must contain a JSON object`);
  }
  return parsed;
}

function atomicWriteJson(filePath, data) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  const tmpPath = path.join(
    path.dirname(filePath),
    `.${path.basename(filePath)}.${process.pid}.${Date.now()}.tmp`,
  );
  fs.writeFileSync(tmpPath, `${JSON.stringify(data, null, 2)}\n`, "utf-8");
  fs.renameSync(tmpPath, filePath);
}

function usage() {
  process.stderr.write(
    "usage: setup_claude_mcp.js <bridge_js> <project_dir> <outbox> <agent> <team> <state_dir> <install_dir>\n",
  );
}

function main(argv = process.argv.slice(2)) {
  if (argv.length !== 7) {
    usage();
    return 2;
  }

  const bridgeJs = stableHomebrewXmuxFilePath(argv[0]);
  const projectDir = absolute(argv[1]);
  const outbox = absolute(argv[2]);
  const agent = argv[3];
  const team = argv[4];
  const stateDir = absolute(argv[5]);
  const installDir = stableHomebrewXmuxInstallDir(argv[6]);

  const configPath = path.join(os.homedir(), ".claude.json");
  const config = loadJson(configPath);

  const projects = config.projects ?? {};
  if (projects === null || Array.isArray(projects) || typeof projects !== "object") {
    throw new Error("error: ~/.claude.json projects must be a JSON object");
  }
  config.projects = projects;

  const project = projects[projectDir] ?? {};
  if (project === null || Array.isArray(project) || typeof project !== "object") {
    throw new Error(`error: Claude project entry for ${projectDir} must be a JSON object`);
  }
  projects[projectDir] = project;

  const servers = project.mcpServers ?? {};
  if (servers === null || Array.isArray(servers) || typeof servers !== "object") {
    throw new Error(`error: Claude mcpServers for ${projectDir} must be a JSON object`);
  }
  project.mcpServers = servers;

  for (const legacyName of LEGACY_NAMES) {
    delete servers[legacyName];
  }

  servers[SERVER_NAME] = {
    type: "stdio",
    command: "node",
    args: [bridgeJs, "--outbox", outbox, "--agent", agent, "--team", team],
    env: {
      XMUX_AGENT: agent,
      XMUX_INSTALL_DIR: installDir,
      XMUX_OUTBOX: outbox,
      XMUX_PROJECT_DIR: projectDir,
      XMUX_STATE_DIR: stateDir,
      XMUX_TEAM: team,
    },
  };

  atomicWriteJson(configPath, config);
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
  stableHomebrewXmuxInstallDir,
  stableHomebrewXmuxFilePath,
};
