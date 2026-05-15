#!/usr/bin/env node
'use strict';

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const { main: codexSetupMain } = require('../codex/setup');
const { main: codexCliMain } = require('../codex/cli');
const { main: claudeMain } = require('../claude/cli');

const HOOK_TAG_KEY = 'XMUX_HOOK_TAG';
const HOOK_TAG_VALUE = 'xmux-claude-harness';
const CODEX_HOOK_TAG_VALUE = 'xmux-codex-harness';
const CLAUDE_SKILL_MARKER = '<!-- XMUX_MANAGED_CLAUDE_XMUX_CODEX_SKILL -->';
const CLAUDE_COMMAND_MARKER = '<!-- XMUX_MANAGED_CLAUDE_XMUX_CODEX_COMMAND -->';
const CLAUDE_SKILL_NAME = 'xmux-codex';

function expandUser(value) {
  const text = String(value || '');
  if (text === '~') return os.homedir();
  if (text.startsWith('~/')) return path.join(os.homedir(), text.slice(2));
  return text;
}

function abs(value) {
  return path.resolve(expandUser(value));
}

function claudeHome() {
  return process.env.CLAUDE_HOME ? abs(process.env.CLAUDE_HOME) : path.join(os.homedir(), '.claude');
}

function projectRoot(start = process.cwd()) {
  let current = abs(start);
  try {
    if (fs.existsSync(current) && !fs.statSync(current).isDirectory()) current = path.dirname(current);
  } catch (_) {
    current = process.cwd();
  }
  while (current && current !== path.dirname(current)) {
    if (fs.existsSync(path.join(current, '.git'))) return current;
    current = path.dirname(current);
  }
  return abs(start || process.cwd());
}

function readJson(filePath, fallback = null) {
  try {
    return JSON.parse(fs.readFileSync(filePath, 'utf8'));
  } catch (_) {
    return fallback;
  }
}

function writeJson(filePath, data) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  const tmp = path.join(path.dirname(filePath), `.${path.basename(filePath)}.${process.pid}.${Date.now()}.tmp`);
  fs.writeFileSync(tmp, `${JSON.stringify(data, null, 2)}\n`, 'utf8');
  fs.renameSync(tmp, filePath);
}

function isManagedClaudeHookCommand(command) {
  const text = String(command || '');
  return (
    text.includes(HOOK_TAG_KEY) && text.includes(HOOK_TAG_VALUE)
  ) || (
    (text.includes('XMUX_PROJECT_DIR=') || text.includes('XMUX_STATE_DIR='))
    && text.includes(' claude hook ')
  );
}

function removeManagedClaudeHooks(settings) {
  if (!settings || typeof settings !== 'object' || !settings.hooks || typeof settings.hooks !== 'object') {
    return 0;
  }
  let removed = 0;
  for (const eventName of Object.keys(settings.hooks)) {
    const current = Array.isArray(settings.hooks[eventName]) ? settings.hooks[eventName] : [];
    const filtered = current
      .map((entry) => {
        if (!entry || typeof entry !== 'object' || !Array.isArray(entry.hooks)) return entry;
        const hooks = entry.hooks.filter((hook) => {
          const command = String((hook || {}).command || '');
          const managed = isManagedClaudeHookCommand(command) && command.includes(' claude hook ');
          if (managed) removed += 1;
          return !managed;
        });
        return { ...entry, hooks };
      })
      .filter((entry) => !entry || !Array.isArray(entry.hooks) || entry.hooks.length > 0);
    if (filtered.length) settings.hooks[eventName] = filtered;
    else delete settings.hooks[eventName];
  }
  if (Object.keys(settings.hooks).length === 0) delete settings.hooks;
  return removed;
}

function isManagedCodexHookCommand(command) {
  const text = String(command || '');
  return text.includes(HOOK_TAG_KEY) && text.includes(CODEX_HOOK_TAG_VALUE) && text.includes(' codex hook ');
}

function removeManagedCodexHooks(settings) {
  if (!settings || typeof settings !== 'object' || !settings.hooks || typeof settings.hooks !== 'object') {
    return 0;
  }
  let removed = 0;
  for (const eventName of Object.keys(settings.hooks)) {
    const current = Array.isArray(settings.hooks[eventName]) ? settings.hooks[eventName] : [];
    const filtered = current
      .map((entry) => {
        if (!entry || typeof entry !== 'object' || !Array.isArray(entry.hooks)) return entry;
        const hooks = entry.hooks.filter((hook) => {
          const managed = isManagedCodexHookCommand((hook || {}).command || '');
          if (managed) removed += 1;
          return !managed;
        });
        return { ...entry, hooks };
      })
      .filter((entry) => !entry || !Array.isArray(entry.hooks) || entry.hooks.length > 0);
    if (filtered.length) settings.hooks[eventName] = filtered;
    else delete settings.hooks[eventName];
  }
  if (Object.keys(settings.hooks).length === 0) delete settings.hooks;
  return removed;
}

function removeManagedFileOrDir(filePath, marker, opts = {}) {
  if (!fs.existsSync(filePath)) return { removed: false, path: filePath, reason: 'missing' };
  const content = fs.readFileSync(filePath, 'utf8');
  if (!content.includes(marker)) return { removed: false, path: filePath, reason: 'unmanaged' };
  const target = opts.remove_dir ? path.dirname(filePath) : filePath;
  if (!opts.dry_run) fs.rmSync(target, { recursive: true, force: true });
  return { removed: true, path: target, reason: '' };
}

function removeManagedClaudeSkill(opts = {}) {
  const skillDir = path.join(claudeHome(), 'skills', CLAUDE_SKILL_NAME);
  const skillFile = path.join(skillDir, 'SKILL.md');
  if (!fs.existsSync(skillFile)) return { removed: false, path: skillDir, reason: 'missing' };
  const content = fs.readFileSync(skillFile, 'utf8');
  if (!content.includes(CLAUDE_SKILL_MARKER)) {
    return { removed: false, path: skillDir, reason: 'unmanaged' };
  }
  if (!opts.dry_run) fs.rmSync(skillDir, { recursive: true, force: true });
  return { removed: true, path: skillDir, reason: '' };
}

function cleanupProjectClaudeResidue(projectDir, opts = {}) {
  const root = projectDir ? abs(projectDir) : projectRoot();
  const claudeDir = path.join(root, '.claude');
  if (!fs.existsSync(claudeDir)) return { project: root, hooks: 0, commands: [], skills: [] };

  const settingsFile = path.join(claudeDir, 'settings.local.json');
  let hooks = 0;
  if (fs.existsSync(settingsFile)) {
    const settings = readJson(settingsFile, {});
    hooks = removeManagedClaudeHooks(settings);
    if (hooks && !opts.dry_run) writeJson(settingsFile, settings);
  }

  const command = removeManagedFileOrDir(
    path.join(claudeDir, 'commands', `${CLAUDE_SKILL_NAME}.md`),
    CLAUDE_COMMAND_MARKER,
    opts,
  );
  const skill = removeManagedFileOrDir(
    path.join(claudeDir, 'skills', CLAUDE_SKILL_NAME, 'SKILL.md'),
    CLAUDE_SKILL_MARKER,
    { ...opts, remove_dir: true },
  );
  return {
    project: root,
    hooks,
    commands: command.removed ? [command.path] : [],
    skills: skill.removed ? [skill.path] : [],
  };
}

function cleanupProjectCodexResidue(projectDir, opts = {}) {
  const root = projectDir ? abs(projectDir) : projectRoot();
  const hooksFile = path.join(root, '.codex', 'hooks.json');
  if (!fs.existsSync(hooksFile)) return { project: root, hooks: 0 };
  const settings = readJson(hooksFile, {});
  const hooks = removeManagedCodexHooks(settings);
  if (hooks && !opts.dry_run) writeJson(hooksFile, settings);
  return { project: root, hooks };
}

function claudeStatus() {
  const settingsFile = path.join(claudeHome(), 'settings.json');
  const skillFile = path.join(claudeHome(), 'skills', CLAUDE_SKILL_NAME, 'SKILL.md');
  const settings = readJson(settingsFile, {});
  const hookCount = settings && settings.hooks && typeof settings.hooks === 'object'
    ? Object.values(settings.hooks)
      .flatMap((entries) => (Array.isArray(entries) ? entries : []))
      .flatMap((entry) => (entry && Array.isArray(entry.hooks) ? entry.hooks : []))
      .filter((hook) => isManagedClaudeHookCommand((hook || {}).command || ''))
      .length
    : 0;
  const skillManaged = fs.existsSync(skillFile)
    && fs.readFileSync(skillFile, 'utf8').includes(CLAUDE_SKILL_MARKER);
  return { settingsFile, skillFile, hookCount, skillManaged };
}

function parseArgs(argv) {
  const opts = {
    doctor: false,
    remove: false,
    quiet: false,
    json: false,
    dry_run: false,
    refresh: false,
    without_codex: false,
    without_claude: false,
    without_skills: false,
    with_skills: true,
    ref: '',
    home: '',
    project: '',
    xmux_install_dir: '',
  };
  for (let i = 0; i < argv.length;) {
    const arg = argv[i];
    if (arg === '--doctor') { opts.doctor = true; i += 1; }
    else if (arg === '--remove') { opts.remove = true; i += 1; }
    else if (arg === '--quiet') { opts.quiet = true; i += 1; }
    else if (arg === '--json') { opts.json = true; i += 1; }
    else if (arg === '--dry-run') { opts.dry_run = true; i += 1; }
    else if (arg === '--refresh') { opts.refresh = true; i += 1; }
    else if (arg === '--without-codex') { opts.without_codex = true; i += 1; }
    else if (arg === '--without-claude') { opts.without_claude = true; i += 1; }
    else if (arg === '--with-skills') { opts.with_skills = true; opts.without_skills = false; i += 1; }
    else if (arg === '--without-skills') { opts.without_skills = true; opts.with_skills = false; i += 1; }
    else if ((arg === '--ref' || arg === '--home' || arg === '--project' || arg === '--xmux-install-dir') && i + 1 < argv.length) {
      opts[arg.slice(2).replace(/-/g, '_')] = argv[i + 1];
      i += 2;
    } else {
      throw new Error(`unknown or incomplete argument: ${arg}`);
    }
  }
  return opts;
}

async function setupClaude(opts) {
  if (opts.dry_run) {
    const status = claudeStatus();
    const residue = cleanupProjectClaudeResidue(opts.project, opts);
    if (!opts.quiet) {
      console.log(`[DRY-RUN] Would install Claude global hooks in ${status.settingsFile}`);
      console.log(`[DRY-RUN] Would install Claude skill at ${status.skillFile}`);
      if (residue.hooks || residue.commands.length || residue.skills.length) {
        console.log(`[DRY-RUN] Would remove project-local Claude XMux residue under ${residue.project}`);
      }
    }
    return 0;
  }
  const args = ['ensure-hooks', '--quiet'];
  const code = await claudeMain(args);
  cleanupProjectClaudeResidue(opts.project, opts);
  return code;
}

async function setupCodexHooks(opts) {
  const codexHome = opts.home ? abs(opts.home) : path.join(os.homedir(), '.codex');
  const hooksFile = path.join(codexHome, 'hooks.json');
  if (opts.dry_run) {
    const residue = cleanupProjectCodexResidue(opts.project, opts);
    if (!opts.quiet) {
      console.log(`[DRY-RUN] Would install Codex global hooks in ${hooksFile}`);
      if (residue.hooks) {
        console.log(`[DRY-RUN] Would remove project-local Codex XMux hooks under ${residue.project}`);
      }
    }
    return 0;
  }
  const args = ['ensure-hooks', '--quiet'];
  if (opts.home) args.push('--home', opts.home);
  const code = await codexCliMain(args);
  cleanupProjectCodexResidue(opts.project, opts);
  return code;
}

function removeClaude(opts) {
  const status = claudeStatus();
  const settings = readJson(status.settingsFile, {});
  const removedHooks = removeManagedClaudeHooks(settings);
  const skill = removeManagedClaudeSkill(opts);
  const residue = cleanupProjectClaudeResidue(opts.project, opts);
  if (!opts.dry_run && removedHooks) writeJson(status.settingsFile, settings);
  if (!opts.quiet) {
    const prefix = opts.dry_run ? '[DRY-RUN]' : '[OK]';
    console.log(`${prefix} Removed XMux-managed Claude hooks: ${removedHooks}`);
    if (skill.removed) console.log(`     removed Claude skill: ${skill.path}`);
    else console.log(`     Claude skill: ${skill.reason}`);
    if (residue.hooks || residue.commands.length || residue.skills.length) {
      console.log(`     removed project-local Claude residue under ${residue.project}`);
    }
  }
  return 0;
}

function claudeDiagnostics() {
  const status = claudeStatus();
  const issues = [];
  const notes = [];
  if (status.hookCount >= 4) notes.push(['OK', `Claude global hooks installed in ${status.settingsFile}`]);
  else issues.push(`Claude global hooks missing or incomplete in ${status.settingsFile}`);
  if (status.skillManaged) notes.push(['OK', `Claude xmux-codex skill installed at ${status.skillFile}`]);
  else issues.push(`Claude xmux-codex skill missing or unmanaged at ${status.skillFile}`);
  return { status, issues, notes };
}

function doctorClaude(opts) {
  const diagnostics = claudeDiagnostics();
  const { issues, notes } = diagnostics;
  if (opts.quiet) return issues.length ? 1 : 0;
  if (opts.json) {
    console.log(JSON.stringify({ status: issues.length ? 'fail' : 'ok', issues, notes }, null, 2));
  } else if (issues.length) {
    console.log('[FAIL] XMux Claude setup is incomplete');
    for (const issue of issues) console.log(`  - ${issue}`);
    for (const [level, note] of notes) console.log(`  - [${level}] ${note}`);
  } else {
    console.log('[OK] XMux Claude setup looks ready');
    for (const [level, note] of notes) console.log(`  - [${level}] ${note}`);
  }
  return issues.length ? 1 : 0;
}

async function main(argv = process.argv.slice(2)) {
  const opts = parseArgs(argv);
  if (opts.doctor) {
    const codexArgs = ['--doctor', ...(opts.quiet || opts.json ? ['--quiet'] : [])];
    if (opts.home) codexArgs.push('--home', opts.home);
    if (opts.project) codexArgs.push('--project', opts.project);
    if (opts.xmux_install_dir) codexArgs.push('--xmux-install-dir', opts.xmux_install_dir);
    const codex = opts.without_codex ? 0 : codexSetupMain(codexArgs);
    if (opts.json) {
      const claudeDiag = opts.without_claude ? { issues: [], notes: [] } : claudeDiagnostics();
      const claude = claudeDiag.issues.length ? 1 : 0;
      console.log(JSON.stringify({
        status: codex || claude ? 'fail' : 'ok',
        codex: { enabled: !opts.without_codex, status: codex ? 'fail' : 'ok' },
        claude: {
          enabled: !opts.without_claude,
          status: claude ? 'fail' : 'ok',
          issues: claudeDiag.issues,
          notes: claudeDiag.notes,
        },
      }, null, 2));
      return codex || claude;
    }
    const claude = opts.without_claude ? 0 : doctorClaude(opts);
    return codex || claude;
  }
  if (opts.remove) {
    const codexArgs = ['--remove', ...(opts.dry_run ? ['--dry-run'] : []), ...(opts.with_skills ? ['--with-skills'] : [])];
    if (opts.home) codexArgs.push('--home', opts.home);
    if (opts.project) codexArgs.push('--project', opts.project);
    if (opts.xmux_install_dir) codexArgs.push('--xmux-install-dir', opts.xmux_install_dir);
    const codex = opts.without_codex ? 0 : codexSetupMain(codexArgs);
    if (!opts.without_codex) cleanupProjectCodexResidue(opts.project, opts);
    const claude = opts.without_claude ? 0 : removeClaude(opts);
    return codex || claude;
  }

  const codexArgs = [
    ...(opts.with_skills ? ['--with-skills'] : ['--without-skills']),
    ...(opts.dry_run ? ['--dry-run'] : []),
    ...(opts.refresh ? ['--refresh'] : []),
  ];
  if (opts.home) codexArgs.push('--home', opts.home);
  if (opts.project) codexArgs.push('--project', opts.project);
  if (opts.ref) codexArgs.push('--ref', opts.ref);
  if (opts.xmux_install_dir) codexArgs.push('--xmux-install-dir', opts.xmux_install_dir);
  const codexConfig = opts.without_codex ? 0 : codexSetupMain(codexArgs);
  const codexHooks = opts.without_codex ? 0 : await setupCodexHooks(opts);
  const codex = codexConfig || codexHooks;
  const claude = opts.without_claude ? 0 : await setupClaude(opts);
  if (!opts.quiet && !opts.dry_run) console.log('[OK] XMux setup complete');
  return codex || claude;
}

if (require.main === module) {
  main()
    .then((code) => { process.exitCode = code; })
    .catch((error) => {
      console.error(`xmux setup: ${error && error.message ? error.message : String(error)}`);
      process.exitCode = 1;
    });
}

module.exports = { main, claudeStatus, removeManagedClaudeHooks, cleanupProjectClaudeResidue };
