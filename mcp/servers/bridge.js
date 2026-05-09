#!/usr/bin/env node
/**
 * mcp/servers/bridge.js
 * Minimal MCP server for xmux.
 * Exposes write_to_lead(text, summary?) so Claude, Gemini, and Copilot
 * teammates can write directly to the XMux lead inbox.
 *
 * Modes:
 *   stdio (default): JSON-RPC over stdin/stdout
 *   HTTP/SSE:        --http <port>  →  GET /sse + POST /messages
 *
 * Config resolution order (first wins):
 *   1. CLI args: --outbox <path> --agent <name> --team <name>
 *   2. Env vars: XMUX_OUTBOX, XMUX_AGENT, XMUX_TEAM
 *
 * If neither is provided the server exits immediately. A previous
 * `.bridge-<agent>.env` mtime-scan fallback was removed: it caused
 * standalone CLI sessions (notably Gemini launched outside xmux-gemini)
 * to silently adopt an unrelated active team's outbox + agent identity
 * and forge write_to_lead entries into the wrong outbox. See
 * docs/investigations/orphan-env-fallback-2026-04-20.md.
 */

'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');

// ── Parse ALL CLI args first (determines mode) ───────────────────────────────

let AGENT_NAME = '';
let OUTBOX = '';
let HTTP_PORT = 0; // 0 = stdio mode
let XMUX_TEAM = '';
let XMUX_INSTALL_DIR = '';

const cliArgs = process.argv.slice(2);
for (let i = 0; i < cliArgs.length; i++) {
  if (cliArgs[i] === '--outbox' && cliArgs[i + 1]) OUTBOX = cliArgs[++i];
  if (cliArgs[i] === '--agent'  && cliArgs[i + 1]) AGENT_NAME = cliArgs[++i];
  if (cliArgs[i] === '--team'   && cliArgs[i + 1]) XMUX_TEAM = cliArgs[++i];
  if (cliArgs[i] === '--http'   && cliArgs[i + 1]) HTTP_PORT = parseInt(cliArgs[++i], 10);
}

// ── Env vars ─────────────────────────────────────────────────────────────────

if (!OUTBOX)     OUTBOX     = process.env.XMUX_OUTBOX || '';
if (!AGENT_NAME) AGENT_NAME = process.env.XMUX_AGENT  || '';
if (!XMUX_TEAM)  XMUX_TEAM  = process.env.XMUX_TEAM || '';
XMUX_INSTALL_DIR = process.env.XMUX_INSTALL_DIR
  ? path.resolve(process.env.XMUX_INSTALL_DIR)
  : '';

// ── Fail fast: reject spawns that never got a team identity ─────────────────
// A standalone CLI (e.g. user runs `gemini` in ~/Desktop) can spawn this
// MCP server via a generic `xmux-bridge` entry in its settings. Without
// explicit OUTBOX/AGENT we refuse to serve — previously a mtime-based
// .bridge-<agent>.env fallback would pick the most-recently-active team
// and the standalone CLI's write_to_lead calls ended up in that team's
// outbox under the wrong `from` (the orphan-env bug, 2026-04-20).

if (!OUTBOX || !AGENT_NAME) {
  process.stderr.write(
    '[xmux-bridge] fatal: no team identity configured.\n' +
    '  Provide --outbox <path> --agent <name> OR env XMUX_OUTBOX/XMUX_AGENT.\n' +
    '  Standalone CLI sessions not launched via xmux claude, xmux gemini, or xmux copilot must not\n' +
    '  register xmux-bridge as an MCP server — remove the entry from that tool\'s\n' +
    '  settings if you see this message.\n'
  );
  process.exit(1);
}

// ── Path validation ──────────────────────────────────────────────────────────

function validateOutboxPath(p) {
  const resolved = path.resolve(p);
  const home = process.env.HOME || '';
  const stateDir = process.env.XMUX_STATE_DIR || path.resolve(home, '.codex', 'xmux');
  const allowedBases = [
    path.resolve(stateDir),
  ];
  return allowedBases.some(base => resolved.startsWith(base + path.sep)) &&
    resolved.endsWith('.json') && !p.includes('..');
}

// ── Outbox write ─────────────────────────────────────────────────────────────

function nowTs() {
  return new Date().toISOString().replace(/(\.\d{3})\d*Z/, '$1Z');
}

function atomicWrite(filePath, data) {
  const dir = path.dirname(path.resolve(filePath));
  const tmp = path.join(dir, `.tmp-${crypto.randomBytes(6).toString('hex')}.json`);
  fs.writeFileSync(tmp, JSON.stringify(data, null, 2), 'utf-8');
  fs.renameSync(tmp, filePath);
}

// mkdir-based cross-process file lock. Coordinates with the Node mailbox
// runtime that uses the same `<path>.lock.d` mutex.
// Prevents lost updates when mailbox writers concurrently read-modify-write
// the same lead inbox JSON file.
function withLock(targetPath, fn) {
  const lockPath = targetPath + '.lock.d';
  let acquired = false;
  for (let i = 0; i < 200; i++) {
    try {
      fs.mkdirSync(lockPath);
      acquired = true;
      break;
    } catch (e) {
      if (e.code !== 'EEXIST') throw e;
      const start = Date.now();
      while (Date.now() - start < 25) {} // busy-wait 25ms
    }
  }
  if (!acquired) throw new Error(`could not acquire lock on ${targetPath}`);
  try {
    return fn();
  } finally {
    try { fs.rmdirSync(lockPath); } catch (_) {}
  }
}

// Cap with read-message preference: when over cap, drop oldest READ
// message first; only drop oldest unread as a last resort. Prevents
// the double-push (response + idle_notification) from silently losing
// unread messages at the 50-cap boundary.
function trimToCap(msgs, cap) {
  while (msgs.length > cap) {
    const idx = msgs.findIndex(m => m.read);
    if (idx >= 0) msgs.splice(idx, 1);
    else msgs.shift();
  }
  return msgs;
}

function mailboxInstallBases() {
  const seen = new Set();
  const bases = [];
  const packageRoot = path.basename(__dirname) === 'servers'
    && path.basename(path.dirname(__dirname)) === 'mcp'
    ? path.dirname(path.dirname(__dirname))
    : __dirname;
  for (const candidate of [XMUX_INSTALL_DIR, packageRoot, __dirname]) {
    if (!candidate) continue;
    const resolved = path.resolve(candidate);
    if (seen.has(resolved)) continue;
    seen.add(resolved);
    bases.push(resolved);
  }
  return bases;
}

function resolveMailboxBackend() {
  for (const base of mailboxInstallBases()) {
    const nodeCli = path.join(base, 'dist', 'bin', 'xmux-mailbox.js');
    if (fs.existsSync(nodeCli)) {
      return {
        kind: 'node',
        command: process.execPath || 'node',
        prefixArgs: [nodeCli],
      };
    }
  }
  return null;
}

function writeToXMuxMailbox(text, summary, requestId, status) {
  const backend = resolveMailboxBackend();
  if (!backend) return null;
  if (!XMUX_TEAM) return null;

  const args = [
    ...backend.prefixArgs,
    'write-response',
    XMUX_TEAM,
    '--from',
    AGENT_NAME,
    '--text',
    text,
    '--status',
    status || 'done',
  ];
  if (summary) args.push('--summary', summary);
  if (requestId) args.push('--request-id', requestId);

  const result = spawnSync(backend.command, args, {
    env: { ...process.env },
    encoding: 'utf8',
    maxBuffer: 1024 * 1024,
  });
  if (result.error) return `error: ${result.error.message || result.error}`;
  if (result.status !== 0) {
    const detail = String(result.stderr || result.stdout || '').trim();
    return `error: xmux mailbox write failed${detail ? `: ${detail}` : ''}`;
  }
  return 'ok: response delivered to lead';
}

function writeToLeadImpl(text, summary, requestId, status) {
  if (!OUTBOX)                    return 'error: XMUX_OUTBOX not set';
  if (!validateOutboxPath(OUTBOX)) return 'error: XMUX_OUTBOX path is invalid or outside allowed directory';
  if (!AGENT_NAME)                return 'error: AGENT_NAME not set (pass --agent or set XMUX_AGENT)';

  const xmuxResult = writeToXMuxMailbox(text, summary, requestId, status);
  if (xmuxResult !== null) return xmuxResult;

  try {
    return withLock(OUTBOX, () => {
      let msgs = [];
      try { msgs = JSON.parse(fs.readFileSync(OUTBOX, 'utf-8')); } catch (_) { msgs = []; }
      const ts1 = nowTs();
      const entry = { from: AGENT_NAME, text, timestamp: ts1, read: false };
      if (summary) entry.summary = summary;
      if (requestId) entry.request_id = requestId;
      if (status) entry.status = status;
      msgs.push(entry);
      trimToCap(msgs, 50);
      const ts2 = nowTs();
      const idlePayload = JSON.stringify({
        type: 'idle_notification', from: AGENT_NAME, idleReason: 'available', timestamp: ts2,
      });
      msgs.push({ from: AGENT_NAME, text: idlePayload, timestamp: ts2, read: false });
      trimToCap(msgs, 50);
      atomicWrite(OUTBOX, msgs);
      return 'ok: response delivered to lead';
    });
  } catch (exc) {
    return `error: ${exc}`;
  }
}

// ── Tool schema ───────────────────────────────────────────────────────────────

const TOOL_SCHEMA = {
  name: 'write_to_lead',
  description:
    'Send your completed response to the Codex lead through the XMux mailbox.',
  inputSchema: {
    type: 'object',
    properties: {
      text:    { type: 'string', description: 'Your full response text.' },
      summary: { type: 'string', description: 'Optional short summary (first sentence, < 60 chars).' },
      request_id: { type: 'string', description: 'Optional XMux request id this response completes.' },
      status: { type: 'string', description: 'Optional response status, defaults to done.' },
    },
    required: ['text'],
  },
};

// ── MCP request handler (returns response object or null) ─────────────────────

function buildResponse(msg) {
  const method = msg.method || '';
  const id = msg.id !== undefined ? msg.id : null;

  if (method === 'initialize') {
    const params = msg.params || {};
    return {
      jsonrpc: '2.0', id,
      result: {
        protocolVersion: params.protocolVersion || '2024-11-05',
        capabilities: { tools: {} },
        serverInfo: { name: 'xmux-bridge', version: '0.3.0' },
      },
    };
  }

  if (method === 'notifications/initialized' || method === 'initialized') {
    return null;
  }

  if (method === 'tools/list') {
    return { jsonrpc: '2.0', id, result: { tools: [TOOL_SCHEMA] } };
  }

  if (method === 'resources/list') {
    return { jsonrpc: '2.0', id, result: { resources: [] } };
  }

  if (method === 'resources/templates/list') {
    return { jsonrpc: '2.0', id, result: { resourceTemplates: [] } };
  }

  if (method === 'tools/call') {
    const params = msg.params || {};
    if (params.name === 'write_to_lead') {
      const args = params.arguments || {};
      const result = writeToLeadImpl(
        args.text || '',
        args.summary || '',
        args.request_id || args.requestId || '',
        args.status || 'done',
      );
      return { jsonrpc: '2.0', id, result: { content: [{ type: 'text', text: result }] } };
    }
    return { jsonrpc: '2.0', id, error: { code: -32601, message: 'Unknown tool' } };
  }

  if (id !== null) {
    return { jsonrpc: '2.0', id, error: { code: -32601, message: `Unknown method: ${method}` } };
  }

  return null;
}

// ── STDIO mode ────────────────────────────────────────────────────────────────
// CRITICAL: register stdin listener FIRST to avoid race condition.
// Provider CLIs send `initialize` immediately after spawn; if stdin isn't
// listening yet the message is lost and the CLI times out (Tools: none).

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
  // Parent CLI closed stdin → exit so MCP subprocess does not linger and
  // continue accepting writes after its intended session is over.
  process.stdin.on('end', () => {
    drain(true);
    process.exit(0);
  });
}

// ── HTTP/SSE mode ─────────────────────────────────────────────────────────────
// Implements the MCP HTTP+SSE transport:
//   GET  /sse            → SSE stream; first event is `endpoint` with POST URL
//   POST /messages?sessionId=<id>  → JSON-RPC request; response via SSE `message` event

function startHttpServer(port) {
  const http = require('http');
  const sessions = new Map(); // sessionId → SSE response

  const server = http.createServer((req, res) => {
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

    if (req.method === 'OPTIONS') {
      res.writeHead(204);
      res.end();
      return;
    }

    const reqUrl = new URL(req.url, `http://127.0.0.1:${port}`);

    if (req.method === 'GET' && reqUrl.pathname === '/sse') {
      const sessionId = crypto.randomBytes(8).toString('hex');
      res.writeHead(200, {
        'Content-Type': 'text/event-stream',
        'Cache-Control': 'no-cache',
        'Connection': 'keep-alive',
      });
      sessions.set(sessionId, res);
      res.write(`event: endpoint\ndata: /messages?sessionId=${sessionId}\n\n`);
      req.on('close', () => sessions.delete(sessionId));
      return;
    }

    if (req.method === 'POST' && reqUrl.pathname === '/messages') {
      const sessionId = reqUrl.searchParams.get('sessionId');
      const sseRes = sessions.get(sessionId);
      let body = '';
      req.on('data', chunk => body += chunk);
      req.on('end', () => {
        res.writeHead(202);
        res.end();
        let msg;
        try { msg = JSON.parse(body); } catch (_) { return; }
        const resp = buildResponse(msg);
        if (resp && sseRes) {
          sseRes.write(`event: message\ndata: ${JSON.stringify(resp)}\n\n`);
        }
      });
      return;
    }

    res.writeHead(404);
    res.end();
  });

  server.listen(port, '127.0.0.1', () => {
    process.stderr.write(`[xmux-bridge] HTTP MCP server on http://127.0.0.1:${port}/sse\n`);
  });
}

// ── Start ─────────────────────────────────────────────────────────────────────

if (HTTP_PORT > 0) {
  startHttpServer(HTTP_PORT);
} else {
  startStdio();
}
