// Task store, persisted to a JSON file on a PersistentVolume.
// Dhruv Davda - 24BCS10203
const fs = require('fs');
const path = require('path');

class TaskStore {
  constructor(dataDir) {
    this.file = path.join(dataDir, 'tasks.json');
    this.tasks = [];
    this.nextId = 1;
    this.load();
  }

  load() {
    try {
      const raw = JSON.parse(fs.readFileSync(this.file, 'utf8'));
      this.tasks = raw.tasks || [];
      this.nextId = raw.nextId || this.tasks.length + 1;
    } catch {
      // First boot: no file yet. Not an error.
      this.tasks = [];
      this.nextId = 1;
    }
  }

  save() {
    fs.mkdirSync(path.dirname(this.file), { recursive: true });
    // Write to a temp file then rename, so a crash mid-write cannot truncate
    // the existing data.
    const tmp = `${this.file}.tmp`;
    fs.writeFileSync(tmp, JSON.stringify({ tasks: this.tasks, nextId: this.nextId }, null, 2));
    fs.renameSync(tmp, this.file);
  }

  list() { return this.tasks; }

  add(title) {
    if (typeof title !== 'string' || !title.trim()) {
      throw new TypeError('title must be a non-empty string');
    }
    if (title.length > 200) throw new RangeError('title must be 200 characters or fewer');
    const task = { id: this.nextId++, title: title.trim(), done: false, created: new Date().toISOString() };
    this.tasks.push(task);
    this.save();
    return task;
  }

  complete(id) {
    const task = this.tasks.find((t) => t.id === Number(id));
    if (!task) return null;
    task.done = true;
    this.save();
    return task;
  }

  stats() {
    return { total: this.tasks.length, done: this.tasks.filter((t) => t.done).length };
  }
}

module.exports = { TaskStore };
