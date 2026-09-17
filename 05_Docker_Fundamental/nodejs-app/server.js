// Hello World HTTP server on the Node standard library only - no npm packages,
// so there is no package.json and no install step in the image.
// Dhruv Davda - 24BCS10203

const http = require('http');
const os = require('os');

const PORT = process.env.PORT || 3000;

const page = `<!DOCTYPE html>
<html lang="en">
<head><meta charset="utf-8"><title>Hello World - Node.js</title></head>
<body style="font-family: system-ui, sans-serif; text-align:center; padding-top:80px;">
  <h1>Hello World from Node.js</h1>
  <p>Dhruv Davda &middot; 24BCS10203 &middot; Group A</p>
  <p>node ${process.version} inside container ${os.hostname()}</p>
</body>
</html>`;

const server = http.createServer((req, res) => {
  console.log(`${req.method} ${req.url}`);
  if (req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status: 'ok' }));
    return;
  }
  res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
  res.end(page);
});

// SIGTERM is what "docker stop" sends first; handling it means the container
// exits immediately instead of waiting out the 10 second grace period.
process.on('SIGTERM', () => {
  console.log('SIGTERM received, shutting down');
  server.close(() => process.exit(0));
});

server.listen(PORT, '0.0.0.0', () => console.log(`listening on 0.0.0.0:${PORT}`));
