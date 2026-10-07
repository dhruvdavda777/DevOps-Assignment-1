// Minimal HTTP server on the Node standard library.
// Dhruv Davda - 24BCS10203
const http = require('http');
const os = require('os');
const { add, percentage, grade } = require('./calc');

const PORT = process.env.PORT || 3000;
const VERSION = process.env.APP_VERSION || 'dev';

const server = http.createServer((req, res) => {
  const url = new URL(req.url, `http://${req.headers.host}`);
  const json = (code, body) => {
    const payload = JSON.stringify(body, null, 2);
    res.writeHead(code, { 'Content-Type': 'application/json' });
    res.end(payload);
  };

  try {
    if (url.pathname === '/healthz') return json(200, { status: 'ok' });
    if (url.pathname === '/readyz') return json(200, { status: 'ready' });

    if (url.pathname === '/grade') {
      const score = Number(url.searchParams.get('score'));
      return json(200, { score, grade: grade(score) });
    }

    if (url.pathname === '/add') {
      const a = Number(url.searchParams.get('a'));
      const b = Number(url.searchParams.get('b'));
      return json(200, { a, b, sum: add(a, b) });
    }

    return json(200, {
      app: 'dhruv-cicd-demo',
      owner: 'Dhruv Davda',
      roll: '24BCS10203',
      group: 'A',
      version: VERSION,
      host: os.hostname(),
      endpoints: ['/healthz', '/readyz', '/add?a=1&b=2', '/grade?score=88'],
    });
  } catch (err) {
    return json(400, { error: err.message });
  }
});

if (require.main === module) {
  server.listen(PORT, '0.0.0.0', () => console.log(`listening on 0.0.0.0:${PORT} version=${VERSION}`));
}

module.exports = server;
