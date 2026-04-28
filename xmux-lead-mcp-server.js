#!/usr/bin/env node
/**
 * xmux-lead-mcp-server.js
 * Stdio-only MCP server exposing XMux lead/team mailbox tools.
 *
 * Mailbox persistence is intentionally delegated to scripts/xmux_mailbox.py.
 */

'use strict';

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

const SERVER_NAME = 'xmux-lead';
const SERVER_VERSION = '0.1.0';
const XMUX_INSTALL_DIR = process.env.XMUX_INSTALL_DIR
  ? path.resolve(process.env.XMUX_INSTALL_DIR)
  : __dirname;
const MAILBOX_SCRIPT = path.join(XMUX_INSTALL_DIR, 'scripts', 'xmux_mailbox.py');
const PYTHON = process.env.PYTHON || process.env.PYTHON3 || 'python3';

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

function runMailbox(subcommand, argv) {
  if (!fs.existsSync(MAILBOX_SCRIPT)) {
    return {
      ok: false,
      error: 'mailbox_cli_missing',
      message: 'scripts/xmux_mailbox.py is not available yet',
      script: MAILBOX_SCRIPT,
      command: subcommand,
    };
  }

  const args = [MAILBOX_SCRIPT, subcommand, ...argv];
  const result = spawnSync(PYTHON, args, {
    env: { ...process.env },
    encoding: 'utf8',
    maxBuffer: 1024 * 1024,
  });

  if (result.error) {
    return {
      ok: false,
      error: 'mailbox_cli_spawn_failed',
      message: String(result.error.message || result.error),
      command: subcommand,
    };
  }

  const parsed = parseJsonOutput(result.stdout);
  if (parsed.ok) return parsed.value;

  const payload = {
    ok: false,
    error: result.status === 0 ? parsed.error : 'mailbox_cli_failed',
    command: subcommand,
    exit_code: result.status,
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
    message: `scripts/xmux_mailbox.py does not expose ${command} JSON output yet`,
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

function startStdio() {
  const readline = require('readline');
  const messageQueue = [];
  let ready = false;

  const rl = readline.createInterface({ input: process.stdin, terminal: false });
  rl.on('line', (line) => {
    if (!line.trim()) return;
    let msg;
    try {
      msg = JSON.parse(line);
    } catch (_) {
      return;
    }

    if (ready) {
      const resp = buildResponse(msg);
      if (resp) process.stdout.write(JSON.stringify(resp) + '\n');
    } else {
      messageQueue.push(msg);
    }
  });
  rl.on('close', () => process.exit(0));

  ready = true;
  for (const msg of messageQueue) {
    const resp = buildResponse(msg);
    if (resp) process.stdout.write(JSON.stringify(resp) + '\n');
  }
  messageQueue.length = 0;
}

startStdio();
