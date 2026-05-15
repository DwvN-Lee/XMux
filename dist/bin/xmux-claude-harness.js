#!/usr/bin/env node
'use strict';

const { main } = require('../claude/cli');

main(process.argv.slice(2))
  .then((code) => process.exit(code))
  .catch((error) => {
    console.error(`xmux claude: ${error && error.message ? error.message : String(error)}`);
    process.exit(1);
  });
