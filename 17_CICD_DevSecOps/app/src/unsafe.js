// NOTE: this file contains DELIBERATE vulnerabilities so the SAST stage has
// something real to find. It is not wired into server.js.
// Dhruv Davda - 24BCS10203
const { exec } = require('child_process');

// VULN 1: command injection - user input concatenated into a shell command
function pingHost(host, cb) {
  exec('ping -c 1 ' + host, cb);
}

// VULN 2: use of eval on caller-supplied input
function calculate(expression) {
  return eval(expression);
}

// VULN 3: weak hashing algorithm
const crypto = require('crypto');
function hashPassword(pw) {
  return crypto.createHash('md5').update(pw).digest('hex');
}

module.exports = { pingHost, calculate, hashPassword };
