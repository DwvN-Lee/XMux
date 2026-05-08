'use strict';

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const { MailboxError } = require('./errors');

function isPlainObject(value) {
  return Boolean(value) && Object.prototype.toString.call(value) === '[object Object]';
}

function sortKeys(value) {
  if (Array.isArray(value)) {
    return value.map(sortKeys);
  }
  if (isPlainObject(value)) {
    const out = {};
    for (const key of Object.keys(value).sort()) {
      out[key] = sortKeys(value[key]);
    }
    return out;
  }
  return value;
}

function ensureAscii(text) {
  return text.replace(/[^\x00-\x7f]/g, (ch) => {
    const code = ch.charCodeAt(0);
    return `\\u${code.toString(16).padStart(4, '0')}`;
  });
}

function toJsonString(data, pretty = false) {
  const normalized = sortKeys(data);
  const json = JSON.stringify(normalized, null, pretty ? 2 : 0);
  return ensureAscii(json);
}

function readJson(filePath, defaultValue) {
  try {
    const raw = fs.readFileSync(filePath, 'utf8');
    return JSON.parse(raw);
  } catch (err) {
    if (err && err.code === 'ENOENT') {
      return defaultValue;
    }
    if (err instanceof SyntaxError) {
      throw new MailboxError(`invalid JSON in ${filePath}: ${err.message}`);
    }
    throw err;
  }
}

function atomicWriteJson(filePath, data) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  const tmpPath = path.join(
    path.dirname(filePath),
    `.tmp-${crypto.randomBytes(6).toString('hex')}.json`,
  );
  fs.writeFileSync(tmpPath, `${toJsonString(data, true)}\n`, 'utf8');
  fs.renameSync(tmpPath, filePath);
}

function printJson(data) {
  process.stdout.write(`${toJsonString(data, false)}\n`);
}

module.exports = {
  atomicWriteJson,
  isPlainObject,
  printJson,
  readJson,
  toJsonString,
};
