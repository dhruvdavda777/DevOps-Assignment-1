const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { TaskStore } = require('../src/store');

function tmpStore() {
  return new TaskStore(fs.mkdtempSync(path.join(os.tmpdir(), 'tb-')));
}

test('starts empty', () => {
  assert.deepStrictEqual(tmpStore().list(), []);
});

test('adds a task', () => {
  const s = tmpStore();
  const t = s.add('write the report');
  assert.strictEqual(t.id, 1);
  assert.strictEqual(t.title, 'write the report');
  assert.strictEqual(t.done, false);
  assert.strictEqual(s.list().length, 1);
});

test('trims whitespace and rejects empty titles', () => {
  const s = tmpStore();
  assert.strictEqual(s.add('  spaced  ').title, 'spaced');
  assert.throws(() => s.add(''), TypeError);
  assert.throws(() => s.add('   '), TypeError);
  assert.throws(() => s.add(null), TypeError);
});

test('rejects an over-long title', () => {
  assert.throws(() => tmpStore().add('x'.repeat(201)), RangeError);
});

test('completes a task and reports stats', () => {
  const s = tmpStore();
  s.add('a'); s.add('b');
  assert.strictEqual(s.complete(1).done, true);
  assert.deepStrictEqual(s.stats(), { total: 2, done: 1 });
  assert.strictEqual(s.complete(999), null);
});

test('persists across instances', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'tb-'));
  new TaskStore(dir).add('survives a restart');
  assert.strictEqual(new TaskStore(dir).list()[0].title, 'survives a restart');
});
