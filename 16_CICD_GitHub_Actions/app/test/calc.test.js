const test = require('node:test');
const assert = require('node:assert');
const { add, percentage, grade } = require('../src/calc');

test('add sums two numbers', () => {
  assert.strictEqual(add(2, 3), 5);
  assert.strictEqual(add(-1, 1), 0);
});

test('add rejects non-numbers', () => {
  assert.throws(() => add('2', 3), TypeError);
});

test('percentage rounds to two decimals', () => {
  assert.strictEqual(percentage(1, 3), 33.33);
  assert.strictEqual(percentage(50, 200), 25);
});

test('percentage rejects a zero denominator', () => {
  assert.throws(() => percentage(1, 0), RangeError);
});

test('grade maps scores to bands', () => {
  assert.strictEqual(grade(95), 'A');
  assert.strictEqual(grade(90), 'A');
  assert.strictEqual(grade(80), 'B');
  assert.strictEqual(grade(60), 'C');
  assert.strictEqual(grade(45), 'D');
  assert.strictEqual(grade(10), 'F');
});

test('grade rejects out-of-range scores', () => {
  assert.throws(() => grade(101), RangeError);
  assert.throws(() => grade(-1), RangeError);
});
