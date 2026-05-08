'use strict';

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const { MailboxError } = require('../runtime/errors');
const { withFileLock } = require('../runtime/lock');
const {
  atomicWriteJson,
  isPlainObject,
  readJson,
  toJsonString,
} = require('../runtime/json');
const { nowTs, sleepMs } = require('../runtime/time');

const SCHEMA_TEAM = 'xmux.team.v1';
const SCHEMA_REQUEST = 'xmux.request.v1';

function randomHex() {
  return crypto.randomBytes(16).toString('hex');
}

function expandUser(value) {
  const text = String(value);
  if (!text.startsWith('~')) {
    return text;
  }
  const home = process.env.HOME;
  if (!home) {
    return text;
  }
  if (text === '~') {
    return home;
  }
  if (text.startsWith('~/')) {
    return path.join(home, text.slice(2));
  }
  return text;
}

function projectRoot(start) {
  let current = path.resolve(expandUser(start));
  while (true) {
    if (fs.existsSync(path.join(current, '.git'))) {
      return current;
    }
    const parent = path.dirname(current);
    if (parent === current) {
      return current;
    }
    current = parent;
  }
}

function safeComponent(value, field) {
  if (value === undefined || value === null) {
    throw new MailboxError(`${field} is required`);
  }
  const text = String(value).trim();
  if (!text || text === '.' || text === '..') {
    throw new MailboxError(`${field} must be a non-empty path component`);
  }
  if (text.includes('/') || text.includes('\\')) {
    throw new MailboxError(`${field} must not contain path separators`);
  }
  return text;
}

function storeRoot(root = null) {
  if (root !== null && root !== undefined) {
    return path.resolve(expandUser(root));
  }
  const envRoot = process.env.XMUX_STATE_DIR;
  if (envRoot) {
    return path.resolve(expandUser(envRoot));
  }
  const projectDir = process.env.XMUX_PROJECT_DIR;
  if (projectDir) {
    return path.resolve(expandUser(projectDir), '.codex', 'xmux');
  }
  return path.join(projectRoot(process.cwd()), '.codex', 'xmux');
}

function teamDir(team, root = null) {
  return path.join(storeRoot(root), 'teams', safeComponent(team, 'team'));
}

function teamJsonPath(team, root = null) {
  return path.join(teamDir(team, root), 'team.json');
}

function inboxPath(team, owner, root = null) {
  return path.join(teamDir(team, root), 'inboxes', `${safeComponent(owner, 'inbox owner')}.json`);
}

function requestPath(team, requestId, root = null) {
  return path.join(teamDir(team, root), 'requests', `${safeComponent(requestId, 'request_id')}.json`);
}

function eventsPath(team, root = null) {
  return path.join(teamDir(team, root), 'events.jsonl');
}

function ensureTeamDirs(teamPath) {
  fs.mkdirSync(teamPath, { recursive: true });
  fs.mkdirSync(path.join(teamPath, 'inboxes'), { recursive: true });
  fs.mkdirSync(path.join(teamPath, 'requests'), { recursive: true });
}

function cloneDefault(value) {
  if (value === undefined || value === null) {
    return value;
  }
  return JSON.parse(JSON.stringify(value));
}

function writeJsonLocked(filePath, data) {
  withFileLock(filePath, () => {
    atomicWriteJson(filePath, data);
  });
}

function updateJsonLocked(filePath, defaultValue, updater) {
  return withFileLock(filePath, () => {
    const data = readJson(filePath, cloneDefault(defaultValue));
    const result = updater(data);
    atomicWriteJson(filePath, data);
    return result;
  });
}

function ensureJsonArray(filePath) {
  if (fs.existsSync(filePath)) {
    return;
  }
  updateJsonLocked(filePath, [], (data) => {
    if (!Array.isArray(data)) {
      throw new MailboxError(`${filePath} is not a JSON array`);
    }
    return null;
  });
}

function ensureTextFile(filePath) {
  if (fs.existsSync(filePath)) {
    return;
  }
  withFileLock(filePath, () => {
    fs.mkdirSync(path.dirname(filePath), { recursive: true });
    if (!fs.existsSync(filePath)) {
      fs.closeSync(fs.openSync(filePath, 'a'));
    }
  });
}

function readTeam(team, root = null) {
  const filePath = teamJsonPath(team, root);
  const data = readJson(filePath, null);
  if (data === null) {
    throw new MailboxError(`team not initialized: ${team}`);
  }
  if (!isPlainObject(data)) {
    throw new MailboxError(`${filePath} is not a JSON object`);
  }
  return data;
}

function leadName(team, root = null) {
  const data = readTeam(team, root);
  const lead = data.lead || {};
  const name = lead.name;
  if (!name) {
    throw new MailboxError(`team has no lead name: ${team}`);
  }
  return name;
}

function teammateNames(data) {
  const members = isPlainObject(data.members) ? data.members : {};
  const names = [];
  for (const [name, member] of Object.entries(members).sort(([a], [b]) => a.localeCompare(b))) {
    if (!isPlainObject(member)) {
      continue;
    }
    if (member.role === 'lead') {
      continue;
    }
    if (member.active === false) {
      continue;
    }
    names.push(name);
  }
  return names;
}

function resolveTeammateTarget(data, requested) {
  const target = safeComponent(requested, 'to');
  const members = isPlainObject(data.members) ? data.members : {};

  const direct = members[target];
  if (isPlainObject(direct)) {
    if (direct.role === 'lead') {
      throw new MailboxError(`target is the lead, not a teammate: ${target}`);
    }
    if (direct.active === false) {
      throw new MailboxError(`teammate is inactive: ${target}`);
    }
    return target;
  }

  const providerMatches = [];
  for (const [name, candidate] of Object.entries(members).sort(([a], [b]) => a.localeCompare(b))) {
    if (!isPlainObject(candidate)) {
      continue;
    }
    if (candidate.role === 'lead') {
      continue;
    }
    if (candidate.active === false) {
      continue;
    }
    if (candidate.provider === target) {
      providerMatches.push(name);
    }
  }

  if (providerMatches.length === 1) {
    return providerMatches[0];
  }
  if (providerMatches.length > 1) {
    throw new MailboxError(
      `ambiguous teammate provider '${target}': ${providerMatches.join(', ')}`,
    );
  }

  const known = teammateNames(data);
  const detail = known.length > 0 ? `; registered active teammates: ${known.join(', ')}` : '';
  throw new MailboxError(`teammate not registered or inactive: ${target}${detail}`);
}

function resolveResponseSender(data, requested) {
  const sender = safeComponent(requested, 'from');
  const members = isPlainObject(data.members) ? data.members : {};
  const member = members[sender];
  if (!isPlainObject(member)) {
    throw new MailboxError(`response sender not registered or inactive: ${sender}`);
  }
  if (member.role === 'lead') {
    throw new MailboxError(`response sender is the lead, not a teammate: ${sender}`);
  }
  if (member.active === false) {
    throw new MailboxError(`response sender not registered or inactive: ${sender}`);
  }
  return sender;
}

function appendEvent(team, event, options = {}) {
  const {
    root = null,
    actor = null,
    target = null,
    requestId = null,
    data = null,
  } = options;
  const filePath = eventsPath(team, root);
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  const record = {
    ts: nowTs(),
    event,
    actor,
    target,
    request_id: requestId,
    data: isPlainObject(data) ? data : {},
  };
  const line = `${toJsonString(record, false)}\n`;
  withFileLock(filePath, () => {
    fs.appendFileSync(filePath, line, 'utf8');
  });
}

function appendInbox(team, owner, entry, root = null) {
  const filePath = inboxPath(team, owner, root);
  updateJsonLocked(filePath, [], (data) => {
    if (!Array.isArray(data)) {
      throw new MailboxError(`${filePath} is not a JSON array`);
    }
    data.push(entry);
    return null;
  });
}

function markLeadResponsesRead(team, requestId, root = null) {
  const lead = leadName(team, root);
  const filePath = inboxPath(team, lead, root);
  return updateJsonLocked(filePath, [], (data) => {
    if (!Array.isArray(data)) {
      throw new MailboxError(`${filePath} is not a JSON array`);
    }
    let marked = 0;
    for (const entry of data) {
      if (
        isPlainObject(entry)
        && entry.type === 'response'
        && entry.request_id === requestId
        && !entry.read
      ) {
        entry.read = true;
        entry.read_at = nowTs();
        marked += 1;
      }
    }
    return marked;
  });
}

function markInboxRead(team, owner, timestamp = null, requestId = null, root = null) {
  const ownerName = safeComponent(owner, 'owner');
  const ts = String(timestamp || '');
  const reqId = String(requestId || '');
  const filePath = inboxPath(team, ownerName, root);

  function entryRequestId(entry) {
    const direct = entry.request_id || entry.requestId || '';
    if (direct) {
      return direct;
    }
    const rawText = entry.text ?? entry.message ?? '';
    if (typeof rawText !== 'string') {
      return '';
    }
    try {
      const nested = JSON.parse(rawText);
      if (isPlainObject(nested)) {
        return nested.request_id || nested.requestId || '';
      }
    } catch (_) {
      return '';
    }
    return '';
  }

  const marked = updateJsonLocked(filePath, [], (data) => {
    if (!Array.isArray(data)) {
      throw new MailboxError(`${filePath} is not a JSON array`);
    }
    let count = 0;
    for (const entry of data) {
      if (!isPlainObject(entry) || entry.read) {
        continue;
      }
      if (ts && entry.timestamp === ts) {
        entry.read = true;
      } else if (reqId && entryRequestId(entry) === reqId) {
        entry.read = true;
      } else if (!ts && !reqId) {
        entry.read = true;
      } else {
        continue;
      }
      entry.read_at = nowTs();
      count += 1;
      if (ts || reqId) {
        break;
      }
    }
    return count;
  });

  return {
    status: 'ok',
    team: safeComponent(team, 'team'),
    owner: ownerName,
    marked,
  };
}

function initTeam(team, leadNameValue, leadProvider, leadPane = null, root = null) {
  const dir = teamDir(team, root);
  ensureTeamDirs(dir);
  const teamName = safeComponent(team, 'team');
  const lead = safeComponent(leadNameValue, 'lead_name');
  const provider = safeComponent(leadProvider, 'lead_provider');
  const filePath = path.join(dir, 'team.json');
  const created = nowTs();

  withFileLock(filePath, () => {
    let data = readJson(filePath, null);
    if (data === null) {
      data = {};
    }
    if (!isPlainObject(data)) {
      throw new MailboxError(`${filePath} is not a JSON object`);
    }
    if (!Object.prototype.hasOwnProperty.call(data, 'schema')) {
      data.schema = SCHEMA_TEAM;
    }
    if (!Object.prototype.hasOwnProperty.call(data, 'name')) {
      data.name = teamName;
    }
    if (!Object.prototype.hasOwnProperty.call(data, 'created_at')) {
      data.created_at = created;
    }
    data.status = 'active';
    data.updated_at = created;

    const priorLead = isPlainObject(data.lead) ? data.lead : {};
    data.lead = {
      name: lead,
      provider,
      pane: leadPane,
      registered_at: priorLead.registered_at || created,
      updated_at: created,
    };

    let members = data.members;
    if (!isPlainObject(members)) {
      members = {};
      data.members = members;
    }
    const existing = isPlainObject(members[lead]) ? members[lead] : {};
    members[lead] = {
      name: lead,
      role: 'lead',
      provider,
      backend: existing.backend || provider,
      pane: leadPane,
      registered_at: existing.registered_at || created,
      updated_at: created,
      active: true,
    };

    atomicWriteJson(filePath, data);
  });

  ensureJsonArray(inboxPath(team, lead, root));
  ensureTextFile(path.join(dir, 'events.jsonl'));
  appendEvent(team, 'team.initialized', {
    root,
    actor: lead,
    data: { lead_provider: provider, lead_pane: leadPane },
  });

  return {
    status: 'ok',
    team: teamName,
    team_dir: dir,
    lead_name: lead,
    lead_provider: provider,
  };
}

function registerMember(team, name, provider, pane = null, backend = 'tmux', root = null) {
  const dir = teamDir(team, root);
  if (!fs.existsSync(path.join(dir, 'team.json'))) {
    throw new MailboxError(`team not initialized: ${team}`);
  }
  const member = safeComponent(name, 'name');
  const providerName = safeComponent(provider, 'provider');
  if (!['claude', 'gemini', 'copilot'].includes(providerName)) {
    throw new MailboxError('teammate provider must be one of: claude, gemini, copilot');
  }
  const backendName = safeComponent(backend, 'backend');
  const filePath = path.join(dir, 'team.json');
  const updated = nowTs();

  const result = updateJsonLocked(filePath, null, (data) => {
    if (!isPlainObject(data)) {
      throw new MailboxError(`${filePath} is not a JSON object`);
    }
    let members = data.members;
    if (!isPlainObject(members)) {
      members = {};
      data.members = members;
    }
    const existing = isPlainObject(members[member]) ? members[member] : {};
    members[member] = {
      name: member,
      role: existing.role || 'member',
      provider: providerName,
      backend: backendName,
      pane,
      registered_at: existing.registered_at || updated,
      updated_at: updated,
      active: true,
    };
    data.updated_at = updated;
    return members[member];
  });

  ensureJsonArray(inboxPath(team, member, root));
  appendEvent(team, 'member.registered', {
    root,
    actor: member,
    data: { provider: providerName, backend: backendName, pane },
  });
  return { status: 'ok', team, member: result };
}

function updateMember(
  team,
  name,
  {
    provider = null,
    pane = null,
    backend = null,
    session = null,
    displayMode = null,
    active = null,
    root = null,
  } = {},
) {
  const dir = teamDir(team, root);
  if (!fs.existsSync(path.join(dir, 'team.json'))) {
    throw new MailboxError(`team not initialized: ${team}`);
  }
  const member = safeComponent(name, 'name');
  const filePath = path.join(dir, 'team.json');
  const updated = nowTs();

  const [result, changes] = updateJsonLocked(filePath, null, (data) => {
    if (!isPlainObject(data)) {
      throw new MailboxError(`${filePath} is not a JSON object`);
    }
    if (!isPlainObject(data.members)) {
      data.members = {};
    }
    const existing = data.members[member];
    if (!isPlainObject(existing)) {
      throw new MailboxError(`member not registered: ${member}`);
    }
    const nextChanges = {};
    const pairs = [
      ['provider', provider],
      ['backend', backend],
      ['pane', pane],
      ['session', session],
      ['display_mode', displayMode],
    ];
    for (const [key, value] of pairs) {
      if (value !== null && value !== undefined) {
        nextChanges[key] = value;
      }
    }
    if (active !== null && active !== undefined) {
      nextChanges.active = Boolean(active);
    }
    Object.assign(existing, nextChanges);
    existing.updated_at = updated;
    data.updated_at = updated;
    return [existing, nextChanges];
  });

  appendEvent(team, 'member.updated', {
    root,
    actor: member,
    data: changes,
  });
  return { status: 'ok', team, member: result };
}

function enqueueRequest(team, to, fromName, message, requestId = null, root = null) {
  const data = readTeam(team, root);
  const target = resolveTeammateTarget(data, to);
  const sender = safeComponent(fromName, 'from');
  const reqId = requestId ? safeComponent(requestId, 'request_id') : randomHex();
  const ts = nowTs();
  const entryId = `msg-${randomHex()}`;
  const entry = {
    id: entryId,
    type: 'request',
    request_id: reqId,
    from: sender,
    to: target,
    text: message,
    timestamp: ts,
    read: false,
    status: 'pending',
  };
  const req = {
    schema: SCHEMA_REQUEST,
    request_id: reqId,
    team: safeComponent(team, 'team'),
    from: sender,
    to: target,
    message,
    status: 'pending',
    created_at: ts,
    updated_at: ts,
    inbox_entry_id: entryId,
    responses: [],
  };
  const reqFile = requestPath(team, reqId, root);
  withFileLock(reqFile, () => {
    if (fs.existsSync(reqFile)) {
      throw new MailboxError(`request already exists: ${reqId}`);
    }
    atomicWriteJson(reqFile, req);
  });
  appendInbox(team, target, entry, root);
  appendEvent(team, 'request.enqueued', {
    root,
    actor: sender,
    target,
    requestId: reqId,
    data: { inbox_entry_id: entryId },
  });
  return { status: 'pending', request_id: reqId, to: target };
}

function writeResponse(
  team,
  fromName,
  text,
  {
    summary = null,
    requestId = null,
    status = 'done',
    root = null,
  } = {},
) {
  if (!['done', 'pending'].includes(status)) {
    throw new MailboxError('status must be done or pending');
  }
  const teamData = readTeam(team, root);
  const lead = (teamData.lead || {}).name;
  if (!lead) {
    throw new MailboxError(`team has no lead name: ${team}`);
  }
  const sender = resolveResponseSender(teamData, fromName);
  const reqId = requestId ? safeComponent(requestId, 'request_id') : null;
  const ts = nowTs();
  const responseId = `rsp-${randomHex()}`;
  const response = {
    id: responseId,
    type: 'response',
    request_id: reqId,
    from: sender,
    to: lead,
    text,
    summary,
    timestamp: ts,
    read: false,
    status,
  };

  appendInbox(team, lead, response, root);

  if (reqId) {
    const filePath = requestPath(team, reqId, root);
    withFileLock(filePath, () => {
      let data = readJson(filePath, null);
      if (data === null) {
        data = {
          schema: SCHEMA_REQUEST,
          request_id: reqId,
          team: safeComponent(team, 'team'),
          from: null,
          to: sender,
          message: null,
          created_at: ts,
          responses: [],
        };
      }
      if (!isPlainObject(data)) {
        throw new MailboxError(`${filePath} is not a JSON object`);
      }
      if (!Array.isArray(data.responses)) {
        data.responses = [];
      }
      data.responses.push(response);
      data.status = status;
      data.updated_at = ts;
      atomicWriteJson(filePath, data);
    });
  }

  appendEvent(team, 'response.written', {
    root,
    actor: sender,
    target: lead,
    requestId: reqId,
    data: { response_id: responseId, status },
  });
  return {
    status,
    request_id: reqId,
    response_id: responseId,
    to: lead,
  };
}

function readResponse(team, requestId, markRead = false, root = null) {
  const reqId = safeComponent(requestId, 'request_id');
  const filePath = requestPath(team, reqId, root);
  const data = readJson(filePath, null);
  if (data === null) {
    return { status: 'missing', request_id: reqId };
  }
  if (!isPlainObject(data)) {
    throw new MailboxError(`${filePath} is not a JSON object`);
  }
  const responses = Array.isArray(data.responses) ? data.responses : [];
  const done = data.status === 'done' && responses.length > 0;
  if (!done) {
    return { status: 'pending', request_id: reqId };
  }
  const marked = markRead ? markLeadResponsesRead(team, reqId, root) : 0;
  const result = {
    status: 'done',
    request_id: reqId,
    response: responses[responses.length - 1],
  };
  if (markRead) {
    result.marked_read = marked;
  }
  return result;
}

function waitResponse(
  team,
  requestId,
  {
    timeout = 60.0,
    interval = 1.0,
    markRead = false,
    root = null,
  } = {},
) {
  const timeoutSeconds = Math.max(Number(timeout) || 0.0, 0.0);
  const intervalSeconds = Math.max(Number(interval) || 0.0, 0.001);
  const deadline = Date.now() + (timeoutSeconds * 1000);

  while (true) {
    const result = readResponse(team, requestId, markRead, root);
    if (result.status === 'done' || result.status === 'missing') {
      result.timed_out = false;
      return result;
    }
    const remainingMs = deadline - Date.now();
    if (remainingMs <= 0) {
      result.timed_out = true;
      return result;
    }
    sleepMs(Math.min(intervalSeconds * 1000, remainingMs));
  }
}

function teamStatus(team, root = null) {
  const dir = teamDir(team, root);
  const filePath = path.join(dir, 'team.json');
  const data = readJson(filePath, null);
  if (data === null) {
    return { status: 'missing', team: safeComponent(team, 'team') };
  }
  if (!isPlainObject(data)) {
    throw new MailboxError(`${filePath} is not a JSON object`);
  }

  const inboxes = {};
  const inboxDir = path.join(dir, 'inboxes');
  if (fs.existsSync(inboxDir)) {
    for (const name of fs.readdirSync(inboxDir).sort()) {
      if (!name.endsWith('.json')) {
        continue;
      }
      const messages = readJson(path.join(inboxDir, name), []);
      if (!Array.isArray(messages)) {
        continue;
      }
      inboxes[path.basename(name, '.json')] = {
        total: messages.length,
        unread: messages.filter((msg) => !msg.read).length,
      };
    }
  }

  const requestCounts = { total: 0, pending: 0, done: 0 };
  const requestsDir = path.join(dir, 'requests');
  if (fs.existsSync(requestsDir)) {
    for (const name of fs.readdirSync(requestsDir).sort()) {
      if (!name.endsWith('.json')) {
        continue;
      }
      const req = readJson(path.join(requestsDir, name), {});
      if (!isPlainObject(req)) {
        continue;
      }
      requestCounts.total += 1;
      const status = req.status || 'pending';
      if (status === 'done') {
        requestCounts.done += 1;
      } else {
        requestCounts.pending += 1;
      }
    }
  }

  return {
    status: 'ok',
    team: data.name || safeComponent(team, 'team'),
    team_status: data.status || 'active',
    team_dir: dir,
    lead: data.lead,
    members: data.members || {},
    inboxes,
    requests: requestCounts,
  };
}

function listEvents(team, status = null, root = null) {
  const filePath = eventsPath(team, root);
  const events = [];
  try {
    const raw = fs.readFileSync(filePath, 'utf8');
    for (const line of raw.split('\n')) {
      const trimmed = line.trim();
      if (!trimmed) {
        continue;
      }
      let record;
      try {
        record = JSON.parse(trimmed);
      } catch (_) {
        continue;
      }
      if (status && ((record.data || {}).status !== status)) {
        continue;
      }
      events.push(record);
    }
  } catch (err) {
    if (!err || err.code !== 'ENOENT') {
      throw err;
    }
  }
  return {
    status: 'ok',
    team: safeComponent(team, 'team'),
    events,
  };
}

function listRequests(team, status = null, root = null) {
  const reqDir = path.join(teamDir(team, root), 'requests');
  const requests = [];
  if (fs.existsSync(reqDir)) {
    for (const name of fs.readdirSync(reqDir).sort()) {
      if (!name.endsWith('.json')) {
        continue;
      }
      const data = readJson(path.join(reqDir, name), null);
      if (!isPlainObject(data)) {
        continue;
      }
      if (status && data.status !== status) {
        continue;
      }
      requests.push(data);
    }
  }
  return {
    status: 'ok',
    team: safeComponent(team, 'team'),
    requests,
  };
}

module.exports = {
  MailboxError,
  enqueueRequest,
  initTeam,
  listEvents,
  listRequests,
  markInboxRead,
  readResponse,
  registerMember,
  teamDir,
  teamStatus,
  updateMember,
  waitResponse,
  writeResponse,
  writeJsonLocked,
  SCHEMA_REQUEST,
  SCHEMA_TEAM,
  storeRoot,
};
