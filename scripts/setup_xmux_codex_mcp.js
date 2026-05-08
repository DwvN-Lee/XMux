#!/usr/bin/env node
"use strict";

const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");

const SERVER_NAME = "xmux_lead";
const MARKETPLACE_NAME = "xmux-local";
const PLUGIN_KEY = `xmux@${MARKETPLACE_NAME}`;
const RULE_BEGIN = "# XMUX_COMMAND_RULE_BEGIN";
const RULE_END = "# XMUX_COMMAND_RULE_END";
const LEGACY_PREFIX = "a" + "mux";
const LEGACY_SERVER_NAMES = [`${LEGACY_PREFIX}_lead`];
const LEGACY_MARKETPLACE_NAMES = [`${LEGACY_PREFIX}-local`];
const LEGACY_PLUGIN_KEYS = [`${LEGACY_PREFIX}@${LEGACY_PREFIX}-local`];
const LOCAL_PLUGIN_CACHE_VERSION = "local";
const SKILL_MARKER = ".xmux-managed-skill";
const DEFAULT_MCP_PACKAGE = "xmux-bridge";
const DEFAULT_MCP_BIN = "xmux-lead-mcp";

function expandUser(value) {
  const text = String(value || "");
  if (text === "~") return os.homedir();
  if (text.startsWith("~/")) return path.join(os.homedir(), text.slice(2));
  return text;
}

function abs(value) {
  return path.resolve(expandUser(value));
}

function stable_homebrew_xmux_install_dir(xmuxInstallDir) {
  const installDir = abs(xmuxInstallDir);
  const marker = `${path.sep}Cellar${path.sep}xmux${path.sep}`;
  if (!installDir.includes(marker) || !installDir.endsWith(`${path.sep}libexec`)) {
    return installDir;
  }
  if (!fs.existsSync(path.join(installDir, "xmux.zsh"))) {
    return installDir;
  }
  const prefix = installDir.split(marker, 1)[0];
  const candidate = path.join(prefix, "opt", "xmux", "libexec");
  return fs.existsSync(path.join(candidate, "xmux.zsh")) ? candidate : installDir;
}

function stable_homebrew_xmux_file_path(inputPath) {
  const resolved = abs(inputPath);
  const installDir = path.dirname(resolved);
  const stableInstallDir = stable_homebrew_xmux_install_dir(installDir);
  if (stableInstallDir === installDir) return resolved;
  const candidate = path.join(stableInstallDir, path.basename(resolved));
  return fs.existsSync(candidate) ? candidate : resolved;
}

function resolve_path_with_node() {
  const nodeBinDir = path.dirname(fs.realpathSync(process.execPath));
  const baseDirs = [nodeBinDir, "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"];
  return [...new Set(baseDirs)].join(":");
}

function read_text(filePath) {
  return fs.existsSync(filePath) ? fs.readFileSync(filePath, "utf8") : "";
}

function write_text(filePath, content) {
  fs.mkdirSync(path.dirname(filePath) || ".", { recursive: true });
  fs.writeFileSync(filePath, content, "utf8");
}

function remove_toml_blocks(content, matcher) {
  const lines = content.split("\n");
  const out = [];
  let skip = false;
  for (const line of lines) {
    const stripped = line.trim();
    if (matcher(stripped)) {
      skip = true;
      continue;
    }
    if (skip && stripped.startsWith("[") && !matcher(stripped)) {
      skip = false;
    }
    if (!skip) out.push(line);
  }
  while (out.length && out[out.length - 1].trim() === "") out.pop();
  return out.join("\n");
}

function remove_xmux_blocks(content) {
  for (const name of [SERVER_NAME, ...LEGACY_SERVER_NAMES]) {
    content = remove_toml_blocks(content, (stripped) => stripped.startsWith(`[mcp_servers.${name}`));
  }
  for (const name of [MARKETPLACE_NAME, ...LEGACY_MARKETPLACE_NAMES]) {
    content = remove_toml_blocks(content, (stripped) => stripped === `[marketplaces.${name}]`);
  }
  for (const key of [PLUGIN_KEY, ...LEGACY_PLUGIN_KEYS]) {
    content = remove_toml_blocks(content, (stripped) => stripped === `[plugins."${key}"]`);
  }
  return content;
}

function remove_marker_block(content, begin, end) {
  const lines = content.split("\n");
  const out = [];
  let skip = false;
  for (const line of lines) {
    const stripped = line.trim();
    if (stripped === begin) {
      skip = true;
      continue;
    }
    if (skip && stripped === end) {
      skip = false;
      continue;
    }
    if (!skip) out.push(line);
  }
  while (out.length && out[out.length - 1].trim() === "") out.pop();
  return out.join("\n");
}

function read_json(filePath) {
  if (!fs.existsSync(filePath)) return null;
  try {
    return JSON.parse(fs.readFileSync(filePath, "utf8"));
  } catch (_) {
    return null;
  }
}

function package_spec_has_version(packageSpec) {
  const text = String(packageSpec || "");
  if (!text) return false;
  if (text.startsWith("@")) return text.indexOf("@", 1) !== -1;
  return text.includes("@");
}

function xmux_version_from_install_dir(xmuxInstallDir) {
  const content = read_text(path.join(abs(xmuxInstallDir), "xmux.zsh"));
  const match = content.match(/^XMUX_VERSION=["']([^"']+)["']/m);
  return match ? match[1] : "";
}

function default_mcp_package_spec(xmuxInstallDir, packageName = "", packageVersion = "") {
  const installPackage = read_json(path.join(abs(xmuxInstallDir), "package.json")) || {};
  const scriptPackage = read_json(path.join(path.dirname(path.dirname(abs(__filename))), "package.json")) || {};
  const name = packageName
    || process.env.XMUX_MCP_NPM_PACKAGE
    || installPackage.name
    || scriptPackage.name
    || DEFAULT_MCP_PACKAGE;
  const version = packageVersion
    || process.env.XMUX_MCP_NPM_VERSION
    || installPackage.version
    || xmux_version_from_install_dir(xmuxInstallDir)
    || scriptPackage.version
    || "";
  if (!version || package_spec_has_version(name)) return name;
  return `${name}@${version}`;
}

function node_mcp_config(serverPath) {
  const normalized = stable_homebrew_xmux_file_path(serverPath);
  return {
    mode: "node",
    command: "node",
    args: [normalized],
    server_path: normalized,
    label: normalized,
  };
}

function npx_mcp_config(packageSpec, binName = DEFAULT_MCP_BIN) {
  return {
    mode: "npx",
    command: "npx",
    args: ["-y", "-p", packageSpec, binName],
    package_spec: packageSpec,
    bin: binName,
    label: `npx -y -p ${packageSpec} ${binName}`,
  };
}

function resolve_mcp_config(xmuxInstallDir, opts = {}) {
  if (opts.server_path) return node_mcp_config(opts.server_path);
  const packageSpec = default_mcp_package_spec(xmuxInstallDir, opts.mcp_package, opts.mcp_version);
  return npx_mcp_config(packageSpec, opts.mcp_bin || DEFAULT_MCP_BIN);
}

function normalize_mcp_config(mcpConfigOrServerPath, xmuxInstallDir = "", opts = {}) {
  if (mcpConfigOrServerPath && typeof mcpConfigOrServerPath === "object") {
    return {
      mode: mcpConfigOrServerPath.mode || "custom",
      command: mcpConfigOrServerPath.command,
      args: [...(mcpConfigOrServerPath.args || [])],
      server_path: mcpConfigOrServerPath.server_path || "",
      package_spec: mcpConfigOrServerPath.package_spec || "",
      bin: mcpConfigOrServerPath.bin || "",
      label: mcpConfigOrServerPath.label || [
        mcpConfigOrServerPath.command,
        ...(mcpConfigOrServerPath.args || []),
      ].join(" "),
    };
  }
  if (mcpConfigOrServerPath) return node_mcp_config(mcpConfigOrServerPath);
  return resolve_mcp_config(xmuxInstallDir, opts);
}

function mcp_args_toml(mcpConfig) {
  return `args = [${mcpConfig.args.map(toml_quote).join(", ")}]`;
}

function build_block(mcpConfigOrServerPath, xmuxInstallDir) {
  const mcpConfig = normalize_mcp_config(mcpConfigOrServerPath, xmuxInstallDir);
  const pathEnv = resolve_path_with_node();
  const home = os.homedir();
  return `[mcp_servers.${SERVER_NAME}]
command = ${toml_quote(mcpConfig.command)}
${mcp_args_toml(mcpConfig)}
startup_timeout_sec = 10
tool_timeout_sec = 300

[mcp_servers.${SERVER_NAME}.env]
PATH = "${pathEnv}"
HOME = "${home}"
XMUX_INSTALL_DIR = "${xmuxInstallDir}"
`;
}

function toml_quote(value) {
  return `"${String(value).replace(/\\/g, "\\\\").replace(/"/g, '\\"')}"`;
}

function parse_toml_assignment_value(line, key) {
  const match = line.match(new RegExp(`^\\s*${key}\\s*=\\s*(.*)\\s*$`));
  if (!match) return null;
  const raw = match[1].trim();
  if (raw.startsWith('"') && raw.endsWith('"')) {
    try {
      return JSON.parse(raw);
    } catch (_) {
      return raw.slice(1, -1);
    }
  }
  return null;
}

function is_xmux_runtime_bin_path(candidatePath, currentXmuxBin) {
  const expanded = abs(candidatePath);
  if (expanded === abs(currentXmuxBin)) return true;
  if (path.basename(expanded) !== "bin") return false;
  const installDir = path.dirname(expanded);
  if (fs.existsSync(path.join(installDir, "xmux.zsh")) && fs.existsSync(path.join(expanded, "xmux"))) {
    return true;
  }
  if (path.basename(installDir) !== "libexec") return false;
  const packageDir = path.dirname(installDir);
  const parentDir = path.dirname(packageDir);
  return path.basename(packageDir) === "xmux" || path.basename(parentDir) === "xmux";
}

function path_with_xmux_bin(xmuxInstallDir, basePath = null) {
  const xmuxBin = path.join(abs(xmuxInstallDir), "bin");
  const source = basePath == null ? resolve_path_with_node() : basePath;
  const parts = source.split(":").filter((part) => part && !is_xmux_runtime_bin_path(part, xmuxBin));
  return [xmuxBin, ...parts].join(":");
}

function ensure_codex_shell_environment(content, xmuxInstallDir) {
  const installDir = abs(xmuxInstallDir);
  const lines = content.split("\n");
  const header = "[shell_environment_policy.set]";
  let start = lines.findIndex((line) => line.trim() === header);
  if (start < 0) {
    const block = [
      header,
      `PATH = ${toml_quote(path_with_xmux_bin(installDir))}`,
      `XMUX_INSTALL_DIR = ${toml_quote(installDir)}`,
    ].join("\n");
    return content.trim() ? `${content.trimEnd()}\n\n${block}\n` : `${block}\n`;
  }

  let end = lines.length;
  for (let i = start + 1; i < lines.length; i += 1) {
    const stripped = lines[i].trim();
    if (stripped.startsWith("[") && stripped.endsWith("]")) {
      end = i;
      break;
    }
  }

  let seenPath = false;
  let seenInstall = false;
  for (let i = start + 1; i < end; i += 1) {
    const stripped = lines[i].trim();
    const key = stripped.includes("=") ? stripped.split("=", 1)[0].trim() : "";
    if (key === "PATH") {
      const current = parse_toml_assignment_value(stripped, "PATH");
      const base = current == null ? resolve_path_with_node() : current;
      lines[i] = `PATH = ${toml_quote(path_with_xmux_bin(installDir, base))}`;
      seenPath = true;
    } else if (key === "XMUX_INSTALL_DIR") {
      lines[i] = `XMUX_INSTALL_DIR = ${toml_quote(installDir)}`;
      seenInstall = true;
    }
  }
  const inserts = [];
  if (!seenPath) inserts.push(`PATH = ${toml_quote(path_with_xmux_bin(installDir))}`);
  if (!seenInstall) inserts.push(`XMUX_INSTALL_DIR = ${toml_quote(installDir)}`);
  if (inserts.length) lines.splice(start + 1, 0, ...inserts);
  return `${lines.join("\n").trimEnd()}\n`;
}

function remove_codex_shell_environment(content, xmuxInstallDir) {
  const lines = content.split("\n");
  const header = "[shell_environment_policy.set]";
  const installBin = path.join(abs(xmuxInstallDir), "bin");
  const start = lines.findIndex((line) => line.trim() === header);
  if (start < 0) return content;

  let end = lines.length;
  for (let i = start + 1; i < lines.length; i += 1) {
    const stripped = lines[i].trim();
    if (stripped.startsWith("[") && stripped.endsWith("]")) {
      end = i;
      break;
    }
  }

  const sectionLines = [];
  for (const line of lines.slice(start + 1, end)) {
    const stripped = line.trim();
    const key = stripped.includes("=") ? stripped.split("=", 1)[0].trim() : "";
    if (key === "XMUX_INSTALL_DIR") continue;
    if (key === "PATH") {
      const current = parse_toml_assignment_value(stripped, "PATH");
      if (current != null) {
        const parts = current.split(":").filter((part) => part && !is_xmux_runtime_bin_path(part, installBin));
        if (parts.length) sectionLines.push(`PATH = ${toml_quote(parts.join(":"))}`);
        continue;
      }
    }
    sectionLines.push(line);
  }

  if (sectionLines.some((line) => line.trim())) {
    lines.splice(start + 1, end - start - 1, ...sectionLines);
  } else {
    lines.splice(start, end - start);
  }
  while (lines.length && lines[lines.length - 1].trim() === "") lines.pop();
  return lines.length ? `${lines.join("\n")}\n` : "";
}

function codex_home(configPath) {
  return path.dirname(abs(configPath));
}

function plugin_cache_root(configPath) {
  return path.join(codex_home(configPath), "plugins", "cache", MARKETPLACE_NAME, "xmux");
}

function plugin_cache_path(configPath) {
  return path.join(plugin_cache_root(configPath), LOCAL_PLUGIN_CACHE_VERSION);
}

function legacy_plugin_cache_roots(configPath) {
  return LEGACY_MARKETPLACE_NAMES.map((marketplace) => (
    path.join(codex_home(configPath), "plugins", "cache", marketplace, LEGACY_PREFIX)
  ));
}

function remove_local_plugin_cache(configPath) {
  const home = codex_home(configPath);
  for (const cachePath of [plugin_cache_root(configPath), ...legacy_plugin_cache_roots(configPath)]) {
    if (fs.existsSync(cachePath)) {
      fs.rmSync(cachePath, { recursive: true, force: true });
    }
    let parent = path.dirname(cachePath);
    while (abs(parent) !== home && abs(parent).startsWith(home)) {
      try {
        fs.rmdirSync(parent);
      } catch (_) {
        break;
      }
      parent = path.dirname(parent);
    }
  }
}

function rules_path(configPath) {
  return path.join(codex_home(configPath), "rules", "default.rules");
}

function install_xmux_command_rule(configPath) {
  const filePath = rules_path(configPath);
  let content = remove_marker_block(read_text(filePath), RULE_BEGIN, RULE_END);
  const block = [
    RULE_BEGIN,
    "# Allow the scoped XMux wrapper command; XMux skills still control operation scope.",
    'prefix_rule(pattern=["xmux"], decision="allow")',
    RULE_END,
  ].join("\n");
  content = content.trim() ? `${content.trimEnd()}\n\n${block}\n` : `${block}\n`;
  write_text(filePath, content);
  return null;
}

function remove_xmux_command_rule(configPath) {
  const filePath = rules_path(configPath);
  const content = remove_marker_block(read_text(filePath), RULE_BEGIN, RULE_END);
  write_text(filePath, content ? `${content}\n` : "");
  return null;
}

function skills_root(configPath) {
  return path.join(codex_home(configPath), "skills");
}

function skill_source_dirs(xmuxInstallDir, skillsDir = "") {
  const candidates = [];
  if (skillsDir) candidates.push(expandUser(skillsDir));
  if (process.env.XMUX_CODEX_SKILLS_DIR) candidates.push(expandUser(process.env.XMUX_CODEX_SKILLS_DIR));
  const seen = new Set();
  const out = [];
  for (const candidate of candidates) {
    const resolved = abs(candidate);
    if (!seen.has(resolved)) {
      seen.add(resolved);
      out.push(resolved);
    }
  }
  return out;
}

function xmux_skill_sources(xmuxInstallDir, skillsDir = "") {
  const sources = new Map();
  for (const base of skill_source_dirs(xmuxInstallDir, skillsDir)) {
    if (!fs.existsSync(base) || !fs.statSync(base).isDirectory()) continue;
    for (const name of fs.readdirSync(base).sort()) {
      if (!name.startsWith("xmux-") || sources.has(name)) continue;
      const source = path.join(base, name);
      if (fs.existsSync(path.join(source, "SKILL.md"))) sources.set(name, source);
    }
  }
  return [...sources.entries()].sort(([a], [b]) => a.localeCompare(b));
}

function is_xmux_managed_skill(candidatePath) {
  return fs.existsSync(candidatePath)
    && fs.statSync(candidatePath).isDirectory()
    && fs.existsSync(path.join(candidatePath, SKILL_MARKER));
}

function install_xmux_skills(configPath, xmuxInstallDir, skillsDir = "") {
  const root = skills_root(configPath);
  const installed = [];
  for (const [name, source] of xmux_skill_sources(xmuxInstallDir, skillsDir)) {
    const dst = path.join(root, name);
    if (fs.existsSync(dst) && !is_xmux_managed_skill(dst)) continue;
    fs.rmSync(dst, { recursive: true, force: true });
    fs.mkdirSync(root, { recursive: true });
    fs.cpSync(source, dst, { recursive: true });
    write_text(path.join(dst, SKILL_MARKER), `${abs(source)}\n`);
    installed.push(name);
  }
  return installed;
}

function remove_xmux_skills(configPath) {
  const root = skills_root(configPath);
  const removed = [];
  if (!fs.existsSync(root) || !fs.statSync(root).isDirectory()) return removed;
  for (const name of fs.readdirSync(root).sort()) {
    if (!name.startsWith("xmux-")) continue;
    const candidate = path.join(root, name);
    if (!is_xmux_managed_skill(candidate)) continue;
    fs.rmSync(candidate, { recursive: true, force: true });
    removed.push(name);
  }
  return removed;
}

function _content_has_xmux_mcp(content, mcpConfigOrServerPath, xmuxInstallDir) {
  const mcpConfig = normalize_mcp_config(mcpConfigOrServerPath, xmuxInstallDir);
  return content.includes(`[mcp_servers.${SERVER_NAME}]`)
    && content.includes(`command = ${toml_quote(mcpConfig.command)}`)
    && content.includes(mcp_args_toml(mcpConfig))
    && content.includes(`XMUX_INSTALL_DIR = "${abs(xmuxInstallDir)}"`)
    && !content.includes("XMUX_PROJECT_DIR =")
    && !content.includes("XMUX_STATE_DIR =");
}

function _content_has_shell_environment(content, xmuxInstallDir) {
  const installBin = path.join(abs(xmuxInstallDir), "bin");
  return content.includes("[shell_environment_policy.set]")
    && content.includes(`XMUX_INSTALL_DIR = "${abs(xmuxInstallDir)}"`)
    && content.includes(installBin);
}

function _rules_have_xmux_command(configPath) {
  const content = read_text(rules_path(configPath));
  return content.includes(RULE_BEGIN)
    && content.includes(RULE_END)
    && content.includes('prefix_rule(pattern=["xmux"], decision="allow")');
}

function _installed_skill_names(configPath) {
  const root = skills_root(configPath);
  if (!fs.existsSync(root) || !fs.statSync(root).isDirectory()) return new Set();
  return new Set(
    fs.readdirSync(root)
      .filter((name) => name.startsWith("xmux-"))
      .filter((name) => fs.existsSync(path.join(root, name, "SKILL.md")))
      .filter((name) => is_xmux_managed_skill(path.join(root, name))),
  );
}

function splitShellWords(command) {
  const words = [];
  let current = "";
  let quote = "";
  for (let i = 0; i < command.length; i += 1) {
    const ch = command[i];
    if (quote) {
      if (ch === quote) quote = "";
      else current += ch;
      continue;
    }
    if (ch === "'" || ch === '"') {
      quote = ch;
    } else if (/\s/.test(ch)) {
      if (current) {
        words.push(current);
        current = "";
      }
    } else {
      current += ch;
    }
  }
  if (current) words.push(current);
  return words;
}

function _xmux_lead_mcp_processes_from_ps(psOutput) {
  const processes = [];
  for (const rawLine of String(psOutput || "").split(/\r?\n/)) {
    const stripped = rawLine.trim();
    if (!stripped.includes("xmux-lead-mcp-server.js")) continue;
    const match = stripped.match(/^(\d+)\s+(.*)$/);
    if (!match) continue;
    const [, pid, command] = match;
    const tokens = splitShellWords(command.trim());
    const serverPath = tokens.find((token) => token.endsWith("xmux-lead-mcp-server.js")) || "";
    if (!serverPath) continue;
    processes.push({ pid, command: command.trim(), server_path: abs(serverPath) });
  }
  return processes;
}

function running_xmux_lead_mcp_processes() {
  if (process.env.XMUX_TEST_PS_OUTPUT !== undefined) {
    return _xmux_lead_mcp_processes_from_ps(process.env.XMUX_TEST_PS_OUTPUT);
  }
  const result = spawnSync("ps", ["-Ao", "pid=,command="], { encoding: "utf8" });
  if (result.status !== 0) return [];
  return _xmux_lead_mcp_processes_from_ps(result.stdout);
}

function _is_homebrew_xmux_mcp_server(serverPath) {
  const normalized = abs(serverPath);
  return normalized.endsWith("xmux-lead-mcp-server.js")
    && normalized.includes(`${path.sep}Cellar${path.sep}xmux${path.sep}`)
    && normalized.includes(`${path.sep}libexec${path.sep}`);
}

function stale_xmux_lead_mcp_processes(expectedMcpConfigOrServerPath, processes = null) {
  const expectedConfig = normalize_mcp_config(expectedMcpConfigOrServerPath);
  if (expectedConfig.mode !== "node") return [];
  const expected = abs(expectedConfig.server_path || expectedConfig.args[0] || "");
  const source = processes || running_xmux_lead_mcp_processes();
  const stale = [];
  for (const proc of source) {
    const serverPath = abs(proc.server_path || "");
    if (!serverPath || serverPath === expected) continue;
    if (!_is_homebrew_xmux_mcp_server(serverPath) && fs.existsSync(serverPath)) continue;
    stale.push({ ...proc, server_path: serverPath });
  }
  return stale;
}

function doctor_codex(configPath, xmuxInstallDir, mcpConfigOrServerPath, skillsDir = "", quiet = false) {
  const mcpConfig = normalize_mcp_config(mcpConfigOrServerPath, xmuxInstallDir);
  const content = read_text(configPath);
  const issues = [];
  const notes = [];

  if (!fs.existsSync(configPath)) issues.push(`missing config: ${configPath}`);
  else if (_content_has_xmux_mcp(content, mcpConfig, xmuxInstallDir)) notes.push(["OK", `mcp command points at ${mcpConfig.label}`]);
  else issues.push("xmux_lead MCP config is missing or stale");

  if (_content_has_shell_environment(content, xmuxInstallDir)) notes.push(["OK", "Codex shell PATH includes XMux bin"]);
  else issues.push("Codex shell PATH/XMUX_INSTALL_DIR setup is missing or stale");

  if (_rules_have_xmux_command(configPath)) notes.push(["OK", `scoped xmux command rule exists in ${rules_path(configPath)}`]);
  else issues.push("scoped xmux command rule is missing");

  const sourceNames = new Set(xmux_skill_sources(xmuxInstallDir, skillsDir).map(([name]) => name));
  const installedNames = _installed_skill_names(configPath);
  if (sourceNames.size) {
    const missing = [...sourceNames].filter((name) => !installedNames.has(name)).sort();
    if (missing.length) issues.push(`missing XMux Codex skills: ${missing.join(", ")}`);
    else notes.push(["OK", `XMux Codex skills installed under ${skills_root(configPath)}`]);
  } else if (installedNames.size) {
    notes.push(["OK", `XMux Codex skills installed under ${skills_root(configPath)}`]);
  } else {
    notes.push(["WARN", "no XMux skill source directory found; pass --skills-dir or set XMUX_CODEX_SKILLS_DIR"]);
  }

  if (fs.existsSync(plugin_cache_path(configPath))) {
    notes.push(["WARN", "legacy XMux plugin cache is present; run xmux setup-codex to remove it"]);
  } else {
    notes.push(["OK", "legacy XMux plugin cache is absent"]);
  }

  const staleProcesses = stale_xmux_lead_mcp_processes(mcpConfig);
  for (const proc of staleProcesses.slice(0, 5)) {
    notes.push([
      "WARN",
      `active xmux_lead MCP process pid ${proc.pid} uses ${proc.server_path}; restart that Codex/XMux session to load the configured server`,
    ]);
  }
  if (staleProcesses.length > 5) {
    notes.push(["WARN", `${staleProcesses.length - 5} more stale xmux_lead MCP process(es) detected`]);
  }

  if (quiet) return issues.length ? 1 : 0;
  if (issues.length) {
    console.log("[FAIL] XMux Codex setup is incomplete");
    for (const issue of issues) console.log(`  - ${issue}`);
    for (const [level, note] of notes) console.log(`  - [${level}] ${note}`);
    console.log("Run: xmux setup-codex");
    return 1;
  }
  console.log("[OK] XMux Codex setup looks ready");
  for (const [level, note] of notes) console.log(`  - [${level}] ${note}`);
  return 0;
}

function parse_args(argv) {
  const opts = {
    remove: false,
    doctor: false,
    quiet: false,
    install_skills: true,
    skills_dir: "",
    home: "",
    project: "",
    xmux_install_dir: "",
    xmux_project_dir: "",
    xmux_state_dir: "",
    server_path: "",
    mcp_package: "",
    mcp_version: "",
    mcp_bin: DEFAULT_MCP_BIN,
  };
  for (let i = 0; i < argv.length;) {
    const arg = argv[i];
    if (arg === "--remove") {
      opts.remove = true; i += 1;
    } else if (arg === "--doctor") {
      opts.doctor = true; i += 1;
    } else if (arg === "--quiet") {
      opts.quiet = true; i += 1;
    } else if (arg === "--without-skills") {
      opts.install_skills = false; i += 1;
    } else if ([
      "--skills-dir",
      "--home",
      "--project",
      "--xmux-install-dir",
      "--xmux-project-dir",
      "--xmux-state-dir",
      "--server-path",
      "--mcp-package",
      "--mcp-version",
      "--mcp-bin",
    ].includes(arg) && i + 1 < argv.length) {
      const key = arg.slice(2).replace(/-/g, "_");
      opts[key] = expandUser(argv[i + 1]);
      i += 2;
    } else {
      console.error(`unknown or incomplete argument: ${arg}`);
      process.exit(2);
    }
  }
  return opts;
}

function default_xmux_project_dir() {
  let current = process.cwd();
  while (current && current !== path.dirname(current)) {
    if (fs.existsSync(path.join(current, ".git"))) return abs(current);
    current = path.dirname(current);
  }
  return abs(process.cwd());
}

function default_xmux_state_dir(projectDir = null) {
  return path.join(projectDir || default_xmux_project_dir(), ".codex", "xmux");
}

function resolve_config_path(opts) {
  if (opts.home && opts.project) {
    console.error("--home and --project are mutually exclusive");
    process.exit(2);
  }
  if (opts.home) return path.join(expandUser(opts.home), "config.toml");
  if (opts.project) return path.join(abs(opts.project), ".codex", "config.toml");
  return path.join(os.homedir(), ".codex", "config.toml");
}

function main(argv = process.argv.slice(2)) {
  const opts = parse_args(argv);
  const configPath = resolve_config_path(opts);
  const scriptInstallDir = path.dirname(path.dirname(abs(__filename)));
  const rawInstallDir = abs(opts.xmux_install_dir || scriptInstallDir);
  const xmuxInstallDir = stable_homebrew_xmux_install_dir(rawInstallDir);
  const xmuxProjectDir = abs(opts.xmux_project_dir || default_xmux_project_dir());
  const xmuxStateDir = abs(opts.xmux_state_dir || default_xmux_state_dir(xmuxProjectDir));
  const mcpConfig = resolve_mcp_config(xmuxInstallDir, opts);

  if (opts.doctor) {
    return doctor_codex(configPath, xmuxInstallDir, mcpConfig, opts.skills_dir, opts.quiet);
  }

  let content = remove_xmux_blocks(read_text(configPath));
  if (opts.remove) {
    content = remove_codex_shell_environment(content, xmuxInstallDir);
    remove_local_plugin_cache(configPath);
    remove_xmux_command_rule(configPath);
    const removedSkills = remove_xmux_skills(configPath);
    write_text(configPath, content ? `${content}` : "");
    console.log(`[OK] Removed XMux Codex lead config from ${configPath}`);
    if (removedSkills.length) console.log(`     removed skills: ${removedSkills.join(", ")}`);
    return 0;
  }

  const globalConfig = path.join(os.homedir(), ".codex", "config.toml");
  if (opts.project && !content.trim() && abs(globalConfig) !== abs(configPath)) {
    content = remove_xmux_blocks(read_text(globalConfig));
  }

  content = ensure_codex_shell_environment(content, xmuxInstallDir);
  const block = build_block(mcpConfig, xmuxInstallDir, xmuxProjectDir, xmuxStateDir);
  if (content && !content.endsWith("\n")) content += "\n";
  const newContent = content.trim() ? `${content}\n${block}` : block;
  write_text(configPath, newContent);
  remove_local_plugin_cache(configPath);
  const installedSkills = opts.install_skills
    ? install_xmux_skills(configPath, xmuxInstallDir, opts.skills_dir)
    : [];
  install_xmux_command_rule(configPath);

  console.log(`[OK] Wrote ${SERVER_NAME} to ${configPath}`);
  console.log(`     mcp: ${mcpConfig.label}`);
  console.log(`     xmux_install_dir: ${xmuxInstallDir}`);
  console.log("     xmux_project_dir: inherited from xmux-launched Codex runtime");
  console.log("     xmux_state_dir: inherited from xmux-launched Codex runtime");
  if (installedSkills.length) console.log(`     skills: ${installedSkills.join(", ")}`);
  else if (opts.install_skills) console.log("     skills: skipped; pass --skills-dir or set XMUX_CODEX_SKILLS_DIR");
  console.log("     plugin_cache: disabled; stale XMux plugin cache removed if present");
  return 0;
}

if (require.main === module) {
  try {
    process.exitCode = main();
  } catch (error) {
    console.error(error && error.stack ? error.stack : String(error));
    process.exitCode = 1;
  }
}

module.exports = {
  remove_xmux_blocks,
  build_block,
  default_mcp_package_spec,
  resolve_mcp_config,
  path_with_xmux_bin,
  ensure_codex_shell_environment,
  install_xmux_command_rule,
  remove_xmux_command_rule,
  _xmux_lead_mcp_processes_from_ps,
  stale_xmux_lead_mcp_processes,
  main,
};
