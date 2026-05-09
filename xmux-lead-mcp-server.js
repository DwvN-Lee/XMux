#!/usr/bin/env node
/**
 * xmux-lead-mcp-server.js
 * Stdio-only MCP server exposing XMux lead/team mailbox tools.
 *
 * Mailbox persistence is delegated to the Node mailbox CLI.
 */

'use strict';

const fs = require('fs');
const path = require('path');
const os = require('os');
const { spawnSync } = require('child_process');

const SERVER_NAME = 'xmux-lead';
const SERVER_VERSION = '0.1.0';
const XMUX_INSTALL_DIR = process.env.XMUX_INSTALL_DIR
  ? path.resolve(process.env.XMUX_INSTALL_DIR)
  : __dirname;
const MAILBOX_BACKEND = resolveMailboxBackend();

const INTERNAL_ERRORS = new Set([
  'mailbox_cli_missing',
  'mailbox_cli_spawn_failed',
  'mailbox_cli_empty_output',
  'mailbox_cli_invalid_json',
  'mailbox_cli_failed',
]);

const TOOL_SCHEMAS = [
  {
    name: 'send_to_teammate',
    description: 'Send a request from the Codex lead to an XMux teammate.',
    inputSchema: {
      type: 'object',
      properties: {
        team: { type: 'string', description: 'XMux team name.' },
        to: { type: 'string', description: 'Teammate name or id.' },
        message: { type: 'string', description: 'Message body for the teammate.' },
        from: { type: 'string', description: 'Sender name. Defaults to codex-lead.' },
        request_id: { type: 'string', description: 'Optional caller-provided request id.' },
      },
      required: ['team', 'to', 'message'],
    },
  },
  {
    name: 'wait_teammate_response',
    description: 'Wait for a teammate response to a request id.',
    inputSchema: {
      type: 'object',
      properties: {
        team: { type: 'string', description: 'XMux team name.' },
        request_id: { type: 'string', description: 'Request id to wait for.' },
        timeout_sec: { type: 'number', description: 'Optional wait timeout in seconds.' },
        interval_sec: { type: 'number', description: 'Optional polling interval in seconds.' },
        mark_read: { type: 'boolean', description: 'Mark the response as read when returned.' },
      },
      required: ['team', 'request_id'],
    },
  },
  {
    name: 'read_teammate_response',
    description: 'Read a teammate response for a request id if one is available.',
    inputSchema: {
      type: 'object',
      properties: {
        team: { type: 'string', description: 'XMux team name.' },
        request_id: { type: 'string', description: 'Request id to read.' },
        mark_read: { type: 'boolean', description: 'Mark the response as read when returned.' },
      },
      required: ['team', 'request_id'],
    },
  },
  {
    name: 'list_teammate_events',
    description: 'List lightweight teammate events or requests when the mailbox CLI supports it.',
    inputSchema: {
      type: 'object',
      properties: {
        team: { type: 'string', description: 'XMux team name.' },
        status: { type: 'string', description: 'Optional status filter.' },
      },
      required: ['team'],
    },
  },
  {
    name: 'team_status',
    description: 'Return mailbox/team status for an XMux team.',
    inputSchema: {
      type: 'object',
      properties: {
        team: { type: 'string', description: 'XMux team name.' },
      },
      required: ['team'],
    },
  },
];

function requiredArgs(args, names) {
  const missing = [];
  for (const name of names) {
    if (args[name] === undefined || args[name] === null || String(args[name]).length === 0) {
      missing.push(name);
    }
  }
  if (missing.length === 0) return null;
  return { ok: false, error: 'invalid_arguments', missing };
}

function addFlag(argv, flag, value) {
  if (value === undefined || value === null || value === '') return;
  argv.push(flag, String(value));
}

function addBoolFlag(argv, flag, value) {
  if (value === true || value === 'true' || value === 1) argv.push(flag);
}

function parseJsonOutput(stdout) {
  const trimmed = String(stdout || '').trim();
  if (!trimmed) return { ok: false, error: 'mailbox_cli_empty_output' };

  try {
    return { ok: true, value: JSON.parse(trimmed) };
  } catch (_) {
    const lines = trimmed.split(/\r?\n/).map(s => s.trim()).filter(Boolean).reverse();
    for (const line of lines) {
      try {
        return { ok: true, value: JSON.parse(line) };
      } catch (_) {}
    }
  }

  return { ok: false, error: 'mailbox_cli_invalid_json' };
}

function mailboxInstallBases() {
  const seen = new Set();
  const bases = [];
  for (const candidate of [XMUX_INSTALL_DIR, __dirname]) {
    if (!candidate) continue;
    const resolved = path.resolve(candidate);
    if (seen.has(resolved)) continue;
    seen.add(resolved);
    bases.push(resolved);
  }
  return bases;
}

function mailboxCandidates() {
  const candidates = [];
  for (const base of mailboxInstallBases()) {
    candidates.push({
      kind: 'node',
      command: process.execPath || 'node',
      prefixArgs: [path.join(base, 'dist', 'bin', 'xmux-mailbox.js')],
    });
  }
  return candidates;
}

function resolveMailboxBackend() {
  for (const candidate of mailboxCandidates()) {
    if (fs.existsSync(candidate.prefixArgs[0])) return candidate;
  }
  return null;
}

function safeTeamName(value) {
  if (value === undefined || value === null) return '';
  const text = String(value).trim();
  if (!text || text === '.' || text === '..') return '';
  if (text.includes('/') || text.includes('\\')) return '';
  return text;
}

function activeTeamRegistryFile(team) {
  if (process.env.XMUX_ACTIVE_TEAM_REGISTRY_DIR) {
    return path.join(path.resolve(process.env.XMUX_ACTIVE_TEAM_REGISTRY_DIR), `${team}.json`);
  }
  const home = process.env.HOME || os.homedir();
  if (!home) return '';
  return path.join(home, '.codex', 'xmux', 'active-teams', `${team}.json`);
}

function readJsonFile(file) {
  try {
    return JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch (_) {
    return null;
  }
}

function validateRegistryState(team, registry) {
  if (!registry || typeof registry !== 'object') return null;
  if (registry.team !== team || registry.status !== 'active') return null;
  if (typeof registry.state_dir !== 'string' || registry.state_dir.length === 0) return null;

  const stateDir = path.resolve(registry.state_dir);
  const teamJsonPath = path.join(stateDir, 'teams', team, 'team.json');
  const teamJson = readJsonFile(teamJsonPath);
  if (!teamJson || typeof teamJson !== 'object') return null;
  if (teamJson.name && teamJson.name !== team) return null;

  const env = { XMUX_STATE_DIR: stateDir };
  if (typeof registry.project_dir === 'string' && registry.project_dir.length > 0) {
    env.XMUX_PROJECT_DIR = path.resolve(registry.project_dir);
  }
  return {
    env,
    project_dir: env.XMUX_PROJECT_DIR || '',
    state_dir: env.XMUX_STATE_DIR,
    registry_team_dir: typeof registry.team_dir === 'string' ? path.resolve(registry.team_dir) : '',
  };
}

function resolveMailboxEnv(argv) {
  const team = safeTeamName(argv && argv[0]);
  const context = {
    env: {},
    source: 'default',
    team,
    registry_file: '',
    project_dir: process.env.XMUX_PROJECT_DIR ? path.resolve(process.env.XMUX_PROJECT_DIR) : '',
    state_dir: process.env.XMUX_STATE_DIR ? path.resolve(process.env.XMUX_STATE_DIR) : '',
    install_dir: XMUX_INSTALL_DIR,
    mailbox_cli: MAILBOX_BACKEND ? MAILBOX_BACKEND.prefixArgs[0] : '',
  };

  if (process.env.XMUX_STATE_DIR) {
    context.source = 'process-env';
    return context;
  }

  if (!team) return context;

  const file = activeTeamRegistryFile(team);
  context.registry_file = file;
  if (!file) return context;

  const registry = readJsonFile(file);
  const resolved = validateRegistryState(team, registry);
  if (!resolved) return context;
  return {
    ...context,
    ...resolved,
    source: 'active-registry',
  };
}

function mailboxContextPayload(context) {
  const payload = {
    install_dir: XMUX_INSTALL_DIR,
    mailbox_cli: MAILBOX_BACKEND ? MAILBOX_BACKEND.prefixArgs[0] : '',
    resolution_source: context && context.source ? context.source : 'default',
  };
  if (context && context.team) payload.team = context.team;
  if (context && context.registry_file) payload.registry_file = context.registry_file;
  if (context && context.project_dir) payload.resolved_project_dir = context.project_dir;
  if (context && context.state_dir) payload.resolved_state_dir = context.state_dir;
  return payload;
}

function runMailbox(subcommand, argv) {
  const resolved = resolveMailboxEnv(argv);
  const context = mailboxContextPayload(resolved);
  if (!MAILBOX_BACKEND) {
    return {
      ok: false,
      error: 'mailbox_cli_missing',
      message: 'dist/bin/xmux-mailbox.js is not available yet',
      candidates: mailboxCandidates().map((candidate) => candidate.prefixArgs[0]),
      command: subcommand,
      ...context,
    };
  }

  const args = [...MAILBOX_BACKEND.prefixArgs, subcommand, ...argv];
  const result = spawnSync(MAILBOX_BACKEND.command, args, {
    env: { ...process.env, ...resolved.env },
    encoding: 'utf8',
    maxBuffer: 1024 * 1024,
  });

  if (result.error) {
    return {
      ok: false,
      error: 'mailbox_cli_spawn_failed',
      message: String(result.error.message || result.error),
      command: subcommand,
      ...context,
    };
  }

  const parsed = parseJsonOutput(result.stdout);
  if (parsed.ok) return parsed.value;

  const payload = {
    ok: false,
    error: result.status === 0 ? parsed.error : 'mailbox_cli_failed',
    command: subcommand,
    exit_code: result.status,
    ...context,
  };
  if (parsed.error && payload.error !== parsed.error) payload.parse_error = parsed.error;
  if (String(result.stderr || '').trim()) payload.stderr = String(result.stderr).trim();
  if (String(result.stdout || '').trim()) payload.stdout = String(result.stdout).trim();
  return payload;
}

function notImplemented(command, detail) {
  const payload = {
    ok: false,
    error: 'not_implemented',
    status: 'not_implemented',
    command,
    message: `mailbox CLI does not expose ${command} JSON output yet`,
  };
  if (detail) payload.detail = detail;
  return payload;
}

function looksUnsupported(result) {
  if (!result || typeof result !== 'object') return false;
  if (INTERNAL_ERRORS.has(result.error)) return true;
  const text = `${result.error || ''} ${result.message || ''} ${result.stderr || ''}`;
  return /unknown|invalid choice|not implemented|unsupported/i.test(text);
}

function sendToTeammate(args) {
  const invalid = requiredArgs(args, ['team', 'to', 'message']);
  if (invalid) return invalid;

  const argv = [];
  argv.push(String(args.team), String(args.to));
  addFlag(argv, '--message', args.message);
  addFlag(argv, '--from', args.from || 'codex-lead');
  addFlag(argv, '--request-id', args.request_id);
  return runMailbox('enqueue-request', argv);
}

function waitTeammateResponse(args) {
  const invalid = requiredArgs(args, ['team', 'request_id']);
  if (invalid) return invalid;

  const argv = [];
  argv.push(String(args.team), String(args.request_id));
  addFlag(argv, '--timeout', args.timeout_sec);
  addFlag(argv, '--interval', args.interval_sec);
  addBoolFlag(argv, '--mark-read', args.mark_read);
  return runMailbox('wait-response', argv);
}

function readTeammateResponse(args) {
  const invalid = requiredArgs(args, ['team', 'request_id']);
  if (invalid) return invalid;

  const argv = [];
  argv.push(String(args.team), String(args.request_id));
  addBoolFlag(argv, '--mark-read', args.mark_read);
  return runMailbox('read-response', argv);
}

function listTeammateEvents(args) {
  const invalid = requiredArgs(args, ['team']);
  if (invalid) return invalid;

  const argv = [];
  argv.push(String(args.team));
  addFlag(argv, '--status', args.status);

  const listEvents = runMailbox('list-events', argv);
  if (!looksUnsupported(listEvents)) return listEvents;

  const listRequests = runMailbox('list-requests', argv);
  if (!looksUnsupported(listRequests)) return listRequests;

  return notImplemented('list-events', { attempts: [listEvents, listRequests] });
}

function teamStatus(args) {
  const invalid = requiredArgs(args, ['team']);
  if (invalid) return invalid;

  const argv = [];
  argv.push(String(args.team));
  return runMailbox('team-status', argv);
}

function toolResult(id, payload) {
  return {
    jsonrpc: '2.0',
    id,
    result: {
      content: [{ type: 'text', text: JSON.stringify(payload) }],
    },
  };
}

function buildResponse(msg) {
  const method = msg.method || '';
  const id = msg.id !== undefined ? msg.id : null;

  if (method === 'initialize') {
    const params = msg.params || {};
    return {
      jsonrpc: '2.0',
      id,
      result: {
        protocolVersion: params.protocolVersion || '2024-11-05',
        capabilities: { tools: {} },
        serverInfo: { name: SERVER_NAME, version: SERVER_VERSION },
      },
    };
  }

  if (method === 'notifications/initialized' || method === 'initialized') {
    return null;
  }

  if (method === 'tools/list') {
    return { jsonrpc: '2.0', id, result: { tools: TOOL_SCHEMAS } };
  }

  if (method === 'resources/list') {
    return { jsonrpc: '2.0', id, result: { resources: [] } };
  }

  if (method === 'resources/templates/list') {
    return { jsonrpc: '2.0', id, result: { resourceTemplates: [] } };
  }

  if (method === 'tools/call') {
    const params = msg.params || {};
    const args = params.arguments || {};

    if (params.name === 'send_to_teammate') return toolResult(id, sendToTeammate(args));
    if (params.name === 'wait_teammate_response') return toolResult(id, waitTeammateResponse(args));
    if (params.name === 'read_teammate_response') return toolResult(id, readTeammateResponse(args));
    if (params.name === 'list_teammate_events') return toolResult(id, listTeammateEvents(args));
    if (params.name === 'team_status') return toolResult(id, teamStatus(args));

    return { jsonrpc: '2.0', id, error: { code: -32601, message: 'Unknown tool' } };
  }

  if (id !== null) {
    return { jsonrpc: '2.0', id, error: { code: -32601, message: `Unknown method: ${method}` } };
  }

  return null;
}

function writeMcpResponse(resp, framed) {
  const body = JSON.stringify(resp);
  if (framed) {
    process.stdout.write(`Content-Length: ${Buffer.byteLength(body, 'utf8')}\r\n\r\n${body}`);
  } else {
    process.stdout.write(body + '\n');
  }
}

function handleStdioMessage(msg, framed) {
  const resp = buildResponse(msg);
  if (resp) writeMcpResponse(resp, framed);
}

function startStdio() {
  let buffer = Buffer.alloc(0);

  function parseContentLengthHeader(header) {
    for (const line of header.split(/\r?\n/)) {
      const match = line.match(/^Content-Length:\s*(\d+)\s*$/i);
      if (match) return Number.parseInt(match[1], 10);
    }
    return null;
  }

  function handleJsonPayload(payload, framed) {
    if (!payload.trim()) return;
    let msg;
    try {
      msg = JSON.parse(payload);
    } catch (_) {
      return;
    }
    handleStdioMessage(msg, framed);
  }

  function drain(flush = false) {
    while (buffer.length) {
      while (buffer[0] === 0x0a || buffer[0] === 0x0d) buffer = buffer.subarray(1);
      if (!buffer.length) return;

      const text = buffer.toString('utf8');
      if (text.toLowerCase().startsWith('content-length:')) {
        let headerEnd = text.indexOf('\r\n\r\n');
        let separatorLength = 4;
        if (headerEnd === -1) {
          headerEnd = text.indexOf('\n\n');
          separatorLength = 2;
        }
        if (headerEnd === -1) return;

        const header = text.slice(0, headerEnd);
        const contentLength = parseContentLengthHeader(header);
        if (!Number.isFinite(contentLength) || contentLength < 0) {
          buffer = Buffer.alloc(0);
          return;
        }

        const bodyStart = Buffer.byteLength(text.slice(0, headerEnd + separatorLength), 'utf8');
        if (buffer.length < bodyStart + contentLength) return;
        const body = buffer.subarray(bodyStart, bodyStart + contentLength).toString('utf8');
        buffer = buffer.subarray(bodyStart + contentLength);
        handleJsonPayload(body, true);
        continue;
      }

      const newline = buffer.indexOf(0x0a);
      if (newline === -1) {
        if (!flush) return;
        const line = buffer.toString('utf8');
        buffer = Buffer.alloc(0);
        handleJsonPayload(line, false);
        return;
      }
      const line = buffer.subarray(0, newline).toString('utf8');
      buffer = buffer.subarray(newline + 1);
      handleJsonPayload(line, false);
    }
  }

  process.stdin.on('data', (chunk) => {
    buffer = Buffer.concat([buffer, chunk]);
    drain(false);
  });
  process.stdin.on('end', () => {
    drain(true);
    process.exit(0);
  });
}

startStdio();
