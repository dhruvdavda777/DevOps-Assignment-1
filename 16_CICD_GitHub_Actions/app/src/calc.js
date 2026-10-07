// Pure functions, unit-tested in CI. No dependencies, so the test job needs no
// npm install - it uses Node's built-in test runner.
// Dhruv Davda - 24BCS10203

function add(a, b) {
  if (typeof a !== 'number' || typeof b !== 'number') {
    throw new TypeError('add expects numbers');
  }
  return a + b;
}

function percentage(part, whole) {
  if (whole === 0) throw new RangeError('whole must not be zero');
  return Math.round((part / whole) * 10000) / 100;
}

// Grade bands used by the /grade endpoint.
function grade(score) {
  if (score < 0 || score > 100) throw new RangeError('score must be 0-100');
  if (score >= 90) return 'A';
  if (score >= 75) return 'B';
  if (score >= 60) return 'C';
  if (score >= 40) return 'D';
  return 'F';
}

module.exports = { add, percentage, grade };
