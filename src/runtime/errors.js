'use strict';

class MailboxError extends Error {
  constructor(message) {
    super(message);
    this.name = 'MailboxError';
  }
}

module.exports = {
  MailboxError,
};
