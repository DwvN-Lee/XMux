#!/usr/bin/env node
"use strict";

const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const FILE_PATH = path.join(os.homedir(), ".copilot", "config.json");

function usage() {
  process.stderr.write("usage: trust_copilot_project.js <path>\n");
}

function main(argv = process.argv.slice(2)) {
  if (argv.length !== 1) {
    usage();
    return 1;
  }

  const projectPath = fs.realpathSync(path.resolve(argv[0]));
  let data = {};
  if (fs.existsSync(FILE_PATH)) {
    try {
      const parsed = JSON.parse(fs.readFileSync(FILE_PATH, "utf-8"));
      if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
        data = parsed;
      }
    } catch {
      data = {};
    }
  }

  const folders = Array.isArray(data.trusted_folders) ? data.trusted_folders : [];
  if (folders.includes(projectPath)) {
    return 0;
  }

  folders.push(projectPath);
  data.trusted_folders = folders;
  fs.mkdirSync(path.dirname(FILE_PATH), { recursive: true });
  fs.writeFileSync(FILE_PATH, `${JSON.stringify(data, null, 2)}\n`, "utf-8");
  return 0;
}

if (require.main === module) {
  process.exitCode = main();
}

module.exports = { main };
