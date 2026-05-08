#!/usr/bin/env node
"use strict";

const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const FILE_PATH = path.join(os.homedir(), ".gemini", "trustedFolders.json");

function usage() {
  process.stderr.write("usage: trust_gemini_project.js <path>\n");
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

  if (data[projectPath] === "TRUST_FOLDER") {
    return 0;
  }

  data[projectPath] = "TRUST_FOLDER";
  fs.mkdirSync(path.dirname(FILE_PATH), { recursive: true });
  fs.writeFileSync(FILE_PATH, `${JSON.stringify(data, null, 2)}\n`, "utf-8");
  return 0;
}

if (require.main === module) {
  process.exitCode = main();
}

module.exports = { main };
