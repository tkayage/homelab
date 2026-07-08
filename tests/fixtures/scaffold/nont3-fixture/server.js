// Minimal non-T3 app: a bare HTTP server listening on the port the Dockerfile
// EXPOSEs (8080). It exists only so the fixture is a plausible containerizable
// repo; scaffold-verify.sh never runs it — the offline suite validates
// generation + manifests, not the app itself.
const http = require('http');

const port = process.env.PORT || 8080;

http
  .createServer((_req, res) => {
    res.writeHead(200, { 'Content-Type': 'text/plain' });
    res.end('ok\n');
  })
  .listen(port, '0.0.0.0');
