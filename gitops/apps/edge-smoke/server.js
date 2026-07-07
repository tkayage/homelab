const crypto = require('crypto');
const http = require('http');

const server = http.createServer((request, response) => {
  const chunks = [];
  request.on('data', (chunk) => chunks.push(chunk));
  request.on('end', () => {
    response.writeHead(200, {'content-type': 'application/json'});
    response.end(JSON.stringify({
      hostname: request.headers.host,
      headers: request.headers,
      bodyBytes: Buffer.concat(chunks).length
    }));
  });
});

server.on('upgrade', (request, socket) => {
  const key = request.headers['sec-websocket-key'];
  const accept = crypto.createHash('sha1')
    .update(`${key}258EAFA5-E914-47DA-95CA-C5AB0DC85B11`)
    .digest('base64');
  socket.write('HTTP/1.1 101 Switching Protocols\r\n');
  socket.write('Upgrade: websocket\r\nConnection: Upgrade\r\n');
  socket.write(`Sec-WebSocket-Accept: ${accept}\r\n\r\n`);
});

server.listen(8080, '0.0.0.0');
