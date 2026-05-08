#!/usr/bin/env node
'use strict';

const { main } = require('../mailbox/cli');

process.exit(main(process.argv.slice(2)));
