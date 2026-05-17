#!/usr/bin/env node
'use strict';

const { main } = require('../../src/xmux/setup');

main(process.argv.slice(2))
  .then((code) => { process.exitCode = code; })
  .catch((error) => {
    console.error(`xmux setup: ${error && error.message ? error.message : String(error)}`);
    process.exitCode = 1;
  });
