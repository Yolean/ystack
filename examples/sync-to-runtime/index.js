// Unlike this example a typical runtime would contain the server and require the handler

const handler = require('./my-handler');

const http = require('http');
const server = http.createServer((req, res) => {
  handler().then(response => {
    res.writeHead(200, { 'Content-Type': 'text/plain' });
    res.end(response);
  });
});

server.listen(8080, '0.0.0.0');
