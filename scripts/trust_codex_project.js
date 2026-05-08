#!/usr/bin/env node
"use strict";

const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const TOML_PATH = path.join(os.homedir(), ".codex", "config.toml");

function usage() {
  process.stderr.write("usage: trust_codex_project.js <path>\n");
}

function main(argv = process.argv.slice(2)) {
  if (argv.length !== 1) {
    usage();
    return 1;
  }

  const projectPath = fs.realpathSync(path.resolve(argv[0]));
  const section = `[projects."${projectPath}"]`;
  let content = "";
  if (fs.existsSync(TOML_PATH)) {
    content = fs.readFileSync(TOML_PATH, "utf-8");
  }

  if (content.includes(section)) {
    return 0;
  }

  const entry = `${section}\ntrust_level = "trusted"\n`;
  fs.mkdirSync(path.dirname(TOML_PATH), { recursive: true });
  if (content && !content.endsWith("\n")) {
    content += "\n";
  }
  fs.writeFileSync(TOML_PATH, `${content}\n${entry}`, "utf-8");
  return 0;
}

if (require.main === module) {
  process.exitCode = main();
}

module.exports = { main };
