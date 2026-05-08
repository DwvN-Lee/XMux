'use strict';

const fs = require('fs');
const path = require('path');

const { sleepMs } = require('./time');

function withFileLock(targetPath, fn, attempts = 200, sleepDelayMs = 25) {
  const lockDir = `${targetPath}.lock.d`;
  const parentDir = path.dirname(lockDir) || '.';

  try {
    fs.mkdirSync(parentDir, { recursive: true });
  } catch (_) {
    // Parent creation can fail for permission/race reasons; mkdir for lock
    // will surface the actionable error.
  }

  let acquired = false;
  for (let i = 0; i < attempts; i += 1) {
    try {
      fs.mkdirSync(lockDir);
      acquired = true;
      break;
    } catch (err) {
      if (err && err.code === 'EEXIST') {
        sleepMs(sleepDelayMs);
        continue;
      }
      if (err && err.code === 'ENOENT') {
        break;
      }
      throw err;
    }
  }

  if (!acquired) {
    throw new Error(`could not acquire lock on ${targetPath}`);
  }

  try {
    return fn();
  } finally {
    try {
      fs.rmdirSync(lockDir);
    } catch (err) {
      if (!err || err.code !== 'ENOENT') {
        // Ignore lock cleanup races; stale lock handling is best-effort.
      }
    }
  }
}

module.exports = {
  withFileLock,
};
