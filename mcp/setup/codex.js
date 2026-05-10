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
const SKILLS_MANIFEST = ".xmux-skills.json";
const PUBLIC_SKILL_NAMES = [
  "xmux-teams",
  "xmux-claude",
  "xmux-gemini",
  "xmux-copilot",
  "xmux-diagnosis",
  "xmux-send-pane",
];
const PUBLIC_SKILL_SET = new Set(PUBLIC_SKILL_NAMES);
const DEFAULT_MCP_PACKAGE = "xmux-bridge";
const DEFAULT_MCP_BIN = "xmux-lead-mcp";
const DEFAULT_MCP_NPX_PREFIX = path.join(".cache", "xmux", "npm-prefix");

function expandUser(value) {
  const text = String(value || "");
  if (text === "~") return os.homedir();
  if (text.startsWith("~/")) return path.join(os.homedir(), text.slice(2));
  return text;
}

function abs(value) {
  return path.resolve(expandUser(value));
}

function xmux_runtime_shell_path(installDir) {
  return path.join(abs(installDir), "runtime", "shell", "xmux.zsh");
}

function has_xmux_runtime(installDir) {
  const root = abs(installDir);
  return fs.existsSync(xmux_runtime_shell_path(root)) || fs.existsSync(path.join(root, "xmux.zsh"));
}

function stable_homebrew_xmux_install_dir(xmuxInstallDir) {
  const installDir = abs(xmuxInstallDir);
  const marker = `${path.sep}Cellar${path.sep}xmux${path.sep}`;
  if (!installDir.includes(marker) || !installDir.endsWith(`${path.sep}libexec`)) {
    return installDir;
  }
  if (!has_xmux_runtime(installDir)) {
    return installDir;
  }
  const prefix = installDir.split(marker, 1)[0];
  const candidate = path.join(prefix, "opt", "xmux", "libexec");
  return has_xmux_runtime(candidate) ? candidate : installDir;
}

function stable_homebrew_xmux_file_path(inputPath) {
  const resolved = abs(inputPath);
  const marker = `${path.sep}Cellar${path.sep}xmux${path.sep}`;
  const libexecSegment = `${path.sep}libexec${path.sep}`;
  const libexecIndex = resolved.indexOf(libexecSegment);
  if (!resolved.includes(marker) || libexecIndex < 0) return resolved;
  const prefix = resolved.split(marker, 1)[0];
  const optDir = path.join(prefix, "opt", "xmux", "libexec");
  const relativePath = resolved.slice(libexecIndex + libexecSegment.length);
  const candidate = path.join(optDir, relativePath);
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

function user_error(message) {
  const error = new Error(message);
  error.user_error = true;
  return error;
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

function package_name_from_spec(packageSpec) {
  const text = String(packageSpec || "");
  if (text.startsWith("@")) {
    const slash = text.indexOf("/");
    if (slash < 0) return text;
    const scope = text.slice(0, slash);
    const rest = text.slice(slash + 1);
    const versionIndex = rest.indexOf("@");
    return `${scope}/${versionIndex < 0 ? rest : rest.slice(0, versionIndex)}`;
  }
  const versionIndex = text.indexOf("@");
  return versionIndex < 0 ? text : text.slice(0, versionIndex);
}

function xmux_version_from_install_dir(xmuxInstallDir) {
  const root = abs(xmuxInstallDir);
  const content = read_text(xmux_runtime_shell_path(root)) || read_text(path.join(root, "xmux.zsh"));
  const match = content.match(/^XMUX_VERSION=["']([^"']+)["']/m);
  return match ? match[1] : "";
}

function default_mcp_package_spec(xmuxInstallDir, packageName = "", packageVersion = "") {
  const installPackage = read_json(path.join(abs(xmuxInstallDir), "package.json")) || {};
  const scriptPackage = read_json(path.join(path.dirname(path.dirname(path.dirname(abs(__filename)))), "package.json")) || {};
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

function default_mcp_npx_prefix(configPath = "") {
  const fallback = path.join(os.homedir(), DEFAULT_MCP_NPX_PREFIX);
  if (!configPath) return fallback;
  const configDir = path.dirname(abs(configPath));
  if (path.basename(configDir) === ".codex") {
    return path.join(path.dirname(configDir), DEFAULT_MCP_NPX_PREFIX);
  }
  return path.join(configDir, DEFAULT_MCP_NPX_PREFIX);
}

function npx_mcp_config(packageSpec, binName = DEFAULT_MCP_BIN, npxPrefix = "") {
  const prefix = abs(npxPrefix || process.env.XMUX_MCP_NPX_PREFIX || default_mcp_npx_prefix());
  return {
    mode: "npx",
    command: "npx",
    args: ["--prefix", prefix, "-y", "-p", packageSpec, binName],
    package_spec: packageSpec,
    bin: binName,
    npx_prefix: prefix,
    label: `npx --prefix ${prefix} -y -p ${packageSpec} ${binName}`,
  };
}

function resolve_mcp_config(xmuxInstallDir, opts = {}) {
  if (opts.server_path) return node_mcp_config(opts.server_path);
  const packageSpec = default_mcp_package_spec(xmuxInstallDir, opts.mcp_package, opts.mcp_version);
  return npx_mcp_config(packageSpec, opts.mcp_bin || DEFAULT_MCP_BIN, opts.mcp_npx_prefix || "");
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
      npx_prefix: mcpConfigOrServerPath.npx_prefix || "",
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

function ensure_mcp_runtime_dirs(mcpConfig) {
  if (mcpConfig.mode === "npx" && mcpConfig.npx_prefix) {
    fs.mkdirSync(mcpConfig.npx_prefix, { recursive: true });
  }
}

function cached_package_root(mcpConfig) {
  if (!mcpConfig || !mcpConfig.npx_prefix || !mcpConfig.package_spec) return "";
  return path.join(abs(mcpConfig.npx_prefix), "node_modules", package_name_from_spec(mcpConfig.package_spec));
}

function cached_mailbox_candidates(mcpConfig) {
  const prefix = mcpConfig && mcpConfig.npx_prefix ? abs(mcpConfig.npx_prefix) : "";
  const root = cached_package_root(mcpConfig);
  return [
    prefix ? path.join(prefix, "node_modules", ".bin", "xmux-mailbox") : "",
    root ? path.join(root, "dist", "bin", "xmux-mailbox.js") : "",
  ].filter(Boolean);
}

function mailbox_source(xmuxInstallDir, mcpConfig) {
  const explicit = process.env.XMUX_MAILBOX_NODE_CLI ? abs(process.env.XMUX_MAILBOX_NODE_CLI) : "";
  if (explicit && fs.existsSync(explicit)) return { ok: true, kind: "env", label: explicit };

  for (const candidate of cached_mailbox_candidates(mcpConfig)) {
    if (fs.existsSync(candidate)) return { ok: true, kind: "npm-cache", label: candidate };
  }

  const bundled = path.join(abs(xmuxInstallDir), "dist", "bin", "xmux-mailbox.js");
  if (fs.existsSync(bundled)) return { ok: true, kind: "brew-bundled", label: bundled };

  const npx = spawnSync("npx", ["--version"], { encoding: "utf8" });
  if (npx.status === 0 && mcpConfig && mcpConfig.mode === "npx" && mcpConfig.package_spec) {
    return { ok: true, kind: "npx", label: `${mcpConfig.package_spec} via ${mcpConfig.npx_prefix}` };
  }

  return { ok: false, kind: "missing", label: "no mailbox CLI source found" };
}

function ensure_mcp_package_cache(mcpConfig, enabled = true) {
  if (!enabled || !mcpConfig || mcpConfig.mode !== "npx") {
    return { status: "skipped", message: "disabled" };
  }
  if (!mcpConfig.npx_prefix || !mcpConfig.package_spec) {
    return { status: "skipped", message: "missing npx package metadata" };
  }
  ensure_mcp_runtime_dirs(mcpConfig);

  const root = cached_package_root(mcpConfig);
  if (root && fs.existsSync(root)) {
    return { status: "ok", message: `using existing cache at ${root}` };
  }

  const npm = spawnSync("npm", [
    "install",
    "--prefix",
    abs(mcpConfig.npx_prefix),
    "--no-save",
    "--omit=dev",
    mcpConfig.package_spec,
  ], { encoding: "utf8" });

  if (npm.status === 0) {
    return { status: "ok", message: `installed ${mcpConfig.package_spec} under ${mcpConfig.npx_prefix}` };
  }

  const detail = (npm.stderr || npm.stdout || "").trim().split(/\r?\n/).slice(-2).join(" ");
  return { status: "failed", message: detail || `npm install exited with ${npm.status}` };
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
  if (has_xmux_runtime(installDir) && fs.existsSync(path.join(expanded, "xmux"))) {
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
    "# Allow the scoped XMux wrapper command; user intent and XMux wrappers control operation scope.",
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

function installed_skills_dir(xmuxInstallDir) {
  return path.join(abs(xmuxInstallDir), "share", "xmux", "skills");
}

function public_skill_name(name) {
  return PUBLIC_SKILL_SET.has(name);
}

function skill_source_dirs(xmuxInstallDir, skillsDir = "", opts = {}) {
  const candidates = [];
  if (skillsDir) candidates.push(expandUser(skillsDir));
  if (opts.include_env !== false && process.env.XMUX_CODEX_SKILLS_DIR) {
    candidates.push(expandUser(process.env.XMUX_CODEX_SKILLS_DIR));
  }
  if (opts.include_installed) candidates.push(installed_skills_dir(xmuxInstallDir));
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

function xmux_skill_sources(xmuxInstallDir, skillsDir = "", opts = {}) {
  const sources = new Map();
  const selected = new Set((opts.selected_skills || []).filter(Boolean));
  for (const base of skill_source_dirs(xmuxInstallDir, skillsDir, opts)) {
    if (!fs.existsSync(base) || !fs.statSync(base).isDirectory()) continue;
    for (const name of fs.readdirSync(base).sort()) {
      if (!name.startsWith("xmux-") || sources.has(name)) continue;
      if (!public_skill_name(name)) continue;
      if (selected.size && !selected.has(name)) continue;
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

function read_skills_manifest(root) {
  const filePath = path.join(root, SKILLS_MANIFEST);
  const data = read_json(filePath);
  if (!data || typeof data !== "object") return { installed: [] };
  if (!Array.isArray(data.installed)) data.installed = [];
  return data;
}

function write_skills_manifest(root, entries, opts = {}) {
  const existing = read_skills_manifest(root);
  const byName = new Map(existing.installed.map((entry) => [entry.name, entry]));
  for (const entry of entries) byName.set(entry.name, entry);
  const installed = [...byName.values()]
    .filter((entry) => fs.existsSync(path.join(root, entry.name, "SKILL.md")))
    .sort((a, b) => a.name.localeCompare(b.name));
  const manifest = {
    xmux_version: opts.xmux_version || "",
    ref: opts.ref || "",
    installed,
  };
  write_text(path.join(root, SKILLS_MANIFEST), `${JSON.stringify(manifest, null, 2)}\n`);
}

function install_xmux_skills(configPath, xmuxInstallDir, opts = {}) {
  const root = skills_root(configPath);
  const installed = [];
  const skipped = [];
  const manifestEntries = [];
  const sources = xmux_skill_sources(xmuxInstallDir, opts.skills_dir || "", opts);
  const force = Boolean(opts.force || opts.refresh);
  const dryRun = Boolean(opts.dry_run);
  const sourceKind = opts.source_kind || (opts.skills_dir ? "skills-dir" : "local");
  const now = new Date().toISOString();

  for (const [name, source] of sources) {
    const dst = path.join(root, name);
    if (fs.existsSync(dst)) {
      if (!is_xmux_managed_skill(dst)) {
        skipped.push({ name, reason: "existing non-XMux skill" });
        continue;
      }
      if (!force) {
        skipped.push({ name, reason: "already installed" });
        continue;
      }
    }
    if (!dryRun) {
      fs.rmSync(dst, { recursive: true, force: true });
      fs.mkdirSync(root, { recursive: true });
      fs.cpSync(source, dst, { recursive: true });
      write_text(path.join(dst, SKILL_MARKER), `${abs(source)}\n`);
    }
    installed.push(name);
    manifestEntries.push({
      name,
      source: sourceKind,
      source_path: abs(source),
      ref: opts.ref || "",
      xmux_version: opts.xmux_version || "",
      installed_at: now,
      mode: "copy",
    });
  }
  if (!dryRun && manifestEntries.length) write_skills_manifest(root, manifestEntries, opts);
  return { installed, skipped, source_count: sources.length };
}

function remove_xmux_skills(configPath, opts = {}) {
  const root = skills_root(configPath);
  const removed = [];
  const dryRun = Boolean(opts.dry_run);
  if (!fs.existsSync(root) || !fs.statSync(root).isDirectory()) return removed;
  for (const name of fs.readdirSync(root).sort()) {
    if (!name.startsWith("xmux-")) continue;
    const candidate = path.join(root, name);
    if (!is_xmux_managed_skill(candidate)) continue;
    if (!dryRun) fs.rmSync(candidate, { recursive: true, force: true });
    removed.push(name);
  }
  if (!dryRun) fs.rmSync(path.join(root, SKILLS_MANIFEST), { force: true });
  return removed;
}

function github_skills_source_dir(xmuxInstallDir, ref) {
  const version = String(ref || "").replace(/^v/, "");
  if (!version || !/^v\d+\.\d+\.\d+(?:[-+].*)?$/.test(ref)) {
    throw user_error("--from-github requires a version tag ref such as v1.2.0");
  }
  const tmpRoot = fs.mkdtempSync(path.join(os.tmpdir(), "xmux-skills-"));
  const archivePath = path.join(tmpRoot, `xmux-${version}.tar.gz`);
  const url = `https://github.com/DwvN-Lee/XMux/releases/download/${ref}/xmux-${version}.tar.gz`;
  const curl = spawnSync("curl", ["-fsSL", "--proto", "=https", "--tlsv1.2", "-o", archivePath, url], { encoding: "utf8" });
  if (curl.status !== 0) {
    const detail = (curl.stderr || curl.stdout || "").trim();
    fs.rmSync(tmpRoot, { recursive: true, force: true });
    throw user_error(detail || `failed to download ${url}`);
  }
  const tar = spawnSync("tar", ["-xzf", archivePath, "-C", tmpRoot], { encoding: "utf8" });
  if (tar.status !== 0) {
    const detail = (tar.stderr || tar.stdout || "").trim();
    fs.rmSync(tmpRoot, { recursive: true, force: true });
    throw user_error(detail || `failed to extract ${archivePath}`);
  }
  const root = fs.readdirSync(tmpRoot)
    .map((name) => path.join(tmpRoot, name))
    .find((candidate) => fs.statSync(candidate).isDirectory());
  const skillsDir = root ? path.join(root, "plugins", "xmux", "skills") : "";
  if (!skillsDir || !fs.existsSync(skillsDir)) {
    fs.rmSync(tmpRoot, { recursive: true, force: true });
    throw user_error(`release archive ${url} does not contain plugins/xmux/skills`);
  }
  return { tmpRoot, skillsDir };
}

function validate_selected_skills(names) {
  const invalid = names.filter((name) => !PUBLIC_SKILL_SET.has(name));
  if (invalid.length) {
    throw user_error(`unsupported XMux skill(s): ${invalid.join(", ")}. Allowed: ${PUBLIC_SKILL_NAMES.join(", ")}`);
  }
}

function default_skills_ref(xmuxInstallDir) {
  const version = xmux_version_from_install_dir(xmuxInstallDir) || "";
  return version ? `v${version}` : "";
}

function install_skills_command(configPath, xmuxInstallDir, opts) {
  validate_selected_skills(opts.selected_skills);
  const github = opts.from_github;
  let tmpRoot = "";
  let skillsDir = opts.skills_dir || "";
  let sourceKind = skillsDir ? "skills-dir" : "local";
  let ref = opts.ref || default_skills_ref(xmuxInstallDir);

  try {
    if (!skillsDir && !github) {
      skillsDir = installed_skills_dir(xmuxInstallDir);
    } else if (!skillsDir && github) {
      const source = github_skills_source_dir(xmuxInstallDir, ref);
      tmpRoot = source.tmpRoot;
      skillsDir = source.skillsDir;
      sourceKind = "github";
    }

    if (!skillsDir || !fs.existsSync(skillsDir)) {
      console.error(`[FAIL] No XMux skill source found at ${skillsDir || installed_skills_dir(xmuxInstallDir)}`);
      console.error("Run with --skills-dir <dir>, or use --from-github --ref v<version>.");
      return 1;
    }

    const result = install_xmux_skills(configPath, xmuxInstallDir, {
      skills_dir: skillsDir,
      selected_skills: opts.selected_skills,
      include_env: false,
      force: opts.force,
      refresh: opts.refresh,
      dry_run: opts.dry_run,
      source_kind: sourceKind,
      ref,
      xmux_version: xmux_version_from_install_dir(xmuxInstallDir) || "",
    });

    const prefix = opts.dry_run ? "[DRY-RUN]" : "[OK]";
    console.log(`${prefix} XMux Codex skills source: ${skillsDir}`);
    if (result.installed.length) console.log(`     installed: ${result.installed.join(", ")}`);
    else console.log("     installed: none");
    for (const item of result.skipped) console.log(`     skipped ${item.name}: ${item.reason}`);
    return 0;
  } finally {
    if (tmpRoot) fs.rmSync(tmpRoot, { recursive: true, force: true });
  }
}

function remove_skills_command(configPath, opts) {
  const removed = remove_xmux_skills(configPath, opts);
  const prefix = opts.dry_run ? "[DRY-RUN]" : "[OK]";
  console.log(`${prefix} Removed XMux-managed Codex skills from ${skills_root(configPath)}`);
  if (removed.length) console.log(`     removed: ${removed.join(", ")}`);
  else console.log("     removed: none");
  return 0;
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
    if (!stripped.includes("mcp/servers/lead.js") && !stripped.includes("xmux-lead-mcp-server.js")) continue;
    const match = stripped.match(/^(\d+)\s+(.*)$/);
    if (!match) continue;
    const [, pid, command] = match;
    const tokens = splitShellWords(command.trim());
    const serverPath = tokens.find((token) => token.endsWith("mcp/servers/lead.js") || token.endsWith("xmux-lead-mcp-server.js")) || "";
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
  return (normalized.endsWith(`${path.sep}mcp${path.sep}servers${path.sep}lead.js`) || normalized.endsWith("xmux-lead-mcp-server.js"))
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
    notes.push(["OK", "optional XMux skills are not configured"]);
  }

  if (fs.existsSync(plugin_cache_path(configPath))) {
    notes.push(["WARN", "legacy XMux plugin cache is present; run xmux setup-codex to remove it"]);
  } else {
    notes.push(["OK", "legacy XMux plugin cache is absent"]);
  }

  const mailbox = mailbox_source(xmuxInstallDir, mcpConfig);
  if (mailbox.ok) notes.push(["OK", `mailbox source: ${mailbox.kind} (${mailbox.label})`]);
  else issues.push(`mailbox source is unavailable: ${mailbox.label}`);

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
    install_skills_command: false,
    remove_skills_command: false,
    with_skills: false,
    skip_skills: false,
    skills_dir: "",
    selected_skills: [],
    from_github: false,
    ref: "",
    force: false,
    refresh: false,
    dry_run: false,
    home: "",
    project: "",
    xmux_install_dir: "",
    xmux_project_dir: "",
    xmux_state_dir: "",
    server_path: "",
    mcp_package: "",
    mcp_version: "",
    mcp_bin: DEFAULT_MCP_BIN,
    mcp_npx_prefix: "",
    cache_mcp: true,
  };
  for (let i = 0; i < argv.length;) {
    const arg = argv[i];
    if (arg === "--remove") {
      opts.remove = true; i += 1;
    } else if (arg === "--doctor") {
      opts.doctor = true; i += 1;
    } else if (arg === "--install-skills") {
      opts.install_skills_command = true; i += 1;
    } else if (arg === "--remove-skills") {
      opts.remove_skills_command = true; i += 1;
    } else if (arg === "--quiet") {
      opts.quiet = true; i += 1;
    } else if (arg === "--with-skills") {
      opts.with_skills = true; i += 1;
    } else if (arg === "--without-skills") {
      opts.skip_skills = true; i += 1;
    } else if (arg === "--cache-mcp") {
      opts.cache_mcp = true; i += 1;
    } else if (arg === "--no-cache-mcp") {
      opts.cache_mcp = false; i += 1;
    } else if (arg === "--from-github") {
      opts.from_github = true; i += 1;
    } else if (arg === "--force") {
      opts.force = true; i += 1;
    } else if (arg === "--refresh") {
      opts.refresh = true; opts.force = true; i += 1;
    } else if (arg === "--dry-run") {
      opts.dry_run = true; i += 1;
    } else if (arg === "--skill" && i + 1 < argv.length) {
      opts.selected_skills.push(argv[i + 1]);
      i += 2;
    } else if ([
      "--skills-dir",
      "--ref",
      "--home",
      "--project",
      "--xmux-install-dir",
      "--xmux-project-dir",
      "--xmux-state-dir",
      "--server-path",
      "--mcp-package",
      "--mcp-version",
      "--mcp-bin",
      "--mcp-npx-prefix",
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
  opts.mcp_npx_prefix = abs(opts.mcp_npx_prefix || process.env.XMUX_MCP_NPX_PREFIX || default_mcp_npx_prefix(configPath));
  const scriptInstallDir = path.dirname(path.dirname(path.dirname(abs(__filename))));
  const rawInstallDir = abs(opts.xmux_install_dir || scriptInstallDir);
  const xmuxInstallDir = stable_homebrew_xmux_install_dir(rawInstallDir);
  const xmuxProjectDir = abs(opts.xmux_project_dir || default_xmux_project_dir());
  const xmuxStateDir = abs(opts.xmux_state_dir || default_xmux_state_dir(xmuxProjectDir));
  const mcpConfig = resolve_mcp_config(xmuxInstallDir, opts);

  if (opts.install_skills_command) {
    return install_skills_command(configPath, xmuxInstallDir, opts);
  }

  if (opts.remove_skills_command) {
    return remove_skills_command(configPath, opts);
  }

  if (opts.remove) {
    let content = remove_xmux_blocks(read_text(configPath));
    content = remove_codex_shell_environment(content, xmuxInstallDir);
    remove_local_plugin_cache(configPath);
    remove_xmux_command_rule(configPath);
    const removedSkills = opts.with_skills ? remove_xmux_skills(configPath) : [];
    write_text(configPath, content ? `${content}` : "");
    console.log(`[OK] Removed XMux Codex lead config from ${configPath}`);
    if (removedSkills.length) console.log(`     removed skills: ${removedSkills.join(", ")}`);
    else if (opts.with_skills) console.log("     removed skills: none");
    return 0;
  }

  if (opts.doctor) {
    return doctor_codex(configPath, xmuxInstallDir, mcpConfig, opts.skills_dir, opts.quiet);
  }

  ensure_mcp_runtime_dirs(mcpConfig);
  const cacheResult = ensure_mcp_package_cache(mcpConfig, opts.cache_mcp);
  if (cacheResult.status === "failed") {
    console.error(`[WARN] XMux MCP package cache failed: ${cacheResult.message}`);
  }

  let content = remove_xmux_blocks(read_text(configPath));

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
  const shouldInstallSkills = !opts.skip_skills
    && (opts.with_skills || opts.skills_dir || process.env.XMUX_CODEX_SKILLS_DIR);
  const skillResult = shouldInstallSkills
    ? install_xmux_skills(configPath, xmuxInstallDir, {
      skills_dir: opts.skills_dir,
      include_installed: opts.with_skills,
      source_kind: (opts.skills_dir || process.env.XMUX_CODEX_SKILLS_DIR) ? "skills-dir" : "local",
      xmux_version: xmux_version_from_install_dir(xmuxInstallDir) || "",
    })
    : { installed: [], skipped: [] };
  const installedSkills = skillResult.installed || [];
  install_xmux_command_rule(configPath);

  console.log(`[OK] Wrote ${SERVER_NAME} to ${configPath}`);
  console.log(`     mcp: ${mcpConfig.label}`);
  if (cacheResult.status === "ok") console.log(`     mcp_cache: ${cacheResult.message}`);
  else if (cacheResult.status === "skipped") console.log(`     mcp_cache: ${cacheResult.message}`);
  console.log(`     xmux_install_dir: ${xmuxInstallDir}`);
  console.log("     xmux_project_dir: inherited from xmux-launched Codex runtime");
  console.log("     xmux_state_dir: inherited from xmux-launched Codex runtime");
  if (installedSkills.length) console.log(`     skills: ${installedSkills.join(", ")}`);
  else if (shouldInstallSkills) {
    console.log("     skills: no importable XMux skills found");
  }
  console.log("     plugin_cache: disabled; stale XMux plugin cache removed if present");
  return 0;
}

if (require.main === module) {
  try {
    process.exitCode = main();
  } catch (error) {
    if (error && error.user_error) console.error(`error: ${error.message}`);
    else console.error(error && error.stack ? error.stack : String(error));
    process.exitCode = 1;
  }
}

module.exports = {
  remove_xmux_blocks,
  build_block,
  default_mcp_package_spec,
  default_mcp_npx_prefix,
  mailbox_source,
  resolve_mcp_config,
  path_with_xmux_bin,
  ensure_codex_shell_environment,
  install_xmux_command_rule,
  remove_xmux_command_rule,
  _xmux_lead_mcp_processes_from_ps,
  stale_xmux_lead_mcp_processes,
  main,
};
