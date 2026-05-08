'use strict';

const {
  MailboxError,
  enqueueRequest,
  initTeam,
  listEvents,
  listRequests,
  markInboxRead,
  readResponse,
  registerMember,
  teamStatus,
  updateMember,
  waitResponse,
  writeResponse,
} = require('./core');
const { printJson } = require('../runtime/json');

const COMMANDS = {
  'init-team': {
    positionals: ['team'],
    options: {
      '--lead-name': { key: 'leadName', required: true, needsValue: true },
      '--lead-provider': { key: 'leadProvider', required: true, needsValue: true },
      '--lead-pane': { key: 'leadPane', needsValue: true },
    },
  },
  'register-member': {
    positionals: ['team', 'name'],
    options: {
      '--provider': { key: 'provider', required: true, needsValue: true },
      '--pane': { key: 'pane', needsValue: true },
      '--backend': { key: 'backend', needsValue: true, defaultValue: 'tmux' },
    },
  },
  'update-member': {
    positionals: ['team', 'name'],
    options: {
      '--provider': { key: 'provider', needsValue: true },
      '--pane': { key: 'pane', needsValue: true },
      '--backend': { key: 'backend', needsValue: true },
      '--session': { key: 'session', needsValue: true },
      '--display-mode': { key: 'displayMode', needsValue: true },
      '--active': { key: 'active', needsValue: true, choices: ['true', 'false'] },
    },
  },
  'enqueue-request': {
    positionals: ['team', 'to'],
    options: {
      '--from': { key: 'fromName', required: true, needsValue: true },
      '--message': { key: 'message', required: true, needsValue: true },
      '--request-id': { key: 'requestId', needsValue: true },
    },
  },
  'write-response': {
    positionals: ['team'],
    options: {
      '--from': { key: 'fromName', required: true, needsValue: true },
      '--text': { key: 'text', required: true, needsValue: true },
      '--summary': { key: 'summary', needsValue: true },
      '--request-id': { key: 'requestId', needsValue: true },
      '--status': {
        key: 'status',
        needsValue: true,
        defaultValue: 'done',
        choices: ['done', 'pending'],
      },
    },
  },
  'read-response': {
    positionals: ['team', 'requestId'],
    options: {
      '--mark-read': { key: 'markRead', needsValue: false, defaultValue: false },
    },
  },
  'wait-response': {
    positionals: ['team', 'requestId'],
    options: {
      '--timeout': { key: 'timeout', needsValue: true, defaultValue: '60.0' },
      '--interval': { key: 'interval', needsValue: true, defaultValue: '1.0' },
      '--mark-read': { key: 'markRead', needsValue: false, defaultValue: false },
    },
  },
  'team-status': {
    positionals: ['team'],
    options: {},
  },
  'mark-read': {
    positionals: ['team', 'owner'],
    options: {
      '--timestamp': { key: 'timestamp', needsValue: true },
      '--request-id': { key: 'requestId', needsValue: true },
    },
  },
  'list-events': {
    positionals: ['team'],
    options: {
      '--status': { key: 'status', needsValue: true },
    },
  },
  'list-requests': {
    positionals: ['team'],
    options: {
      '--status': { key: 'status', needsValue: true },
    },
  },
};

function parseArgs(argv) {
  if (!argv || argv.length === 0) {
    throw new MailboxError('command is required');
  }
  const command = argv[0];
  const spec = COMMANDS[command];
  if (!spec) {
    throw new MailboxError(`unknown command: ${command}`);
  }

  const parsed = { command };
  const positionals = [];

  for (let i = 1; i < argv.length; i += 1) {
    const token = argv[i];
    if (token.startsWith('--')) {
      const opt = spec.options[token];
      if (!opt) {
        throw new MailboxError(`unknown option for ${command}: ${token}`);
      }
      if (!opt.needsValue) {
        parsed[opt.key] = true;
        continue;
      }
      if (i + 1 >= argv.length) {
        throw new MailboxError(`${token} requires a value`);
      }
      const value = argv[i + 1];
      i += 1;
      if (opt.choices && !opt.choices.includes(value)) {
        throw new MailboxError(`${token} must be one of: ${opt.choices.join(', ')}`);
      }
      parsed[opt.key] = value;
      continue;
    }
    positionals.push(token);
  }

  if (positionals.length < spec.positionals.length) {
    const missing = spec.positionals[positionals.length];
    throw new MailboxError(`${missing} is required`);
  }
  if (positionals.length > spec.positionals.length) {
    throw new MailboxError(`unexpected argument: ${positionals[spec.positionals.length]}`);
  }
  spec.positionals.forEach((name, index) => {
    parsed[name] = positionals[index];
  });

  for (const [flag, opt] of Object.entries(spec.options)) {
    if (parsed[opt.key] === undefined && opt.defaultValue !== undefined) {
      parsed[opt.key] = opt.defaultValue;
    }
    if (opt.required && (parsed[opt.key] === undefined || parsed[opt.key] === null)) {
      throw new MailboxError(`${flag} is required`);
    }
  }

  if (parsed.active !== undefined) {
    parsed.active = parsed.active === 'true';
  }
  if (parsed.timeout !== undefined) {
    parsed.timeout = Number(parsed.timeout);
    if (!Number.isFinite(parsed.timeout)) {
      throw new MailboxError('--timeout must be a valid number');
    }
  }
  if (parsed.interval !== undefined) {
    parsed.interval = Number(parsed.interval);
    if (!Number.isFinite(parsed.interval)) {
      throw new MailboxError('--interval must be a valid number');
    }
  }

  return parsed;
}

function runCommand(args) {
  switch (args.command) {
    case 'init-team':
      return initTeam(args.team, args.leadName, args.leadProvider, args.leadPane);
    case 'register-member':
      return registerMember(args.team, args.name, args.provider, args.pane, args.backend);
    case 'update-member':
      return updateMember(args.team, args.name, {
        provider: args.provider,
        pane: args.pane,
        backend: args.backend,
        session: args.session,
        displayMode: args.displayMode,
        active: args.active,
      });
    case 'enqueue-request':
      return enqueueRequest(args.team, args.to, args.fromName, args.message, args.requestId);
    case 'write-response':
      return writeResponse(args.team, args.fromName, args.text, {
        summary: args.summary,
        requestId: args.requestId,
        status: args.status,
      });
    case 'read-response':
      return readResponse(args.team, args.requestId, Boolean(args.markRead));
    case 'wait-response':
      return waitResponse(args.team, args.requestId, {
        timeout: args.timeout,
        interval: args.interval,
        markRead: Boolean(args.markRead),
      });
    case 'team-status':
      return teamStatus(args.team);
    case 'mark-read':
      return markInboxRead(args.team, args.owner, args.timestamp, args.requestId);
    case 'list-events':
      return listEvents(args.team, args.status);
    case 'list-requests':
      return listRequests(args.team, args.status);
    default:
      throw new MailboxError(`unknown command: ${args.command}`);
  }
}

function main(argv = process.argv.slice(2)) {
  try {
    const args = parseArgs(argv);
    const result = runCommand(args);
    printJson(result);
    return 0;
  } catch (err) {
    const detail = err && err.message ? err.message : String(err);
    process.stderr.write(`xmux-mailbox: ${detail}\n`);
    return 1;
  }
}

module.exports = {
  main,
  parseArgs,
  runCommand,
};

if (require.main === module) {
  process.exit(main(process.argv.slice(2)));
}
