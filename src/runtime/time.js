'use strict';

function nowTs() {
  return new Date().toISOString();
}

function sleepMs(ms) {
  const waitMs = Math.max(0, Number(ms) || 0);
  if (waitMs <= 0) {
    return;
  }
  try {
    const buffer = new SharedArrayBuffer(4);
    const view = new Int32Array(buffer);
    Atomics.wait(view, 0, 0, waitMs);
  } catch (_) {
    const end = Date.now() + waitMs;
    while (Date.now() < end) {
      // busy wait fallback
    }
  }
}

module.exports = {
  nowTs,
  sleepMs,
};
