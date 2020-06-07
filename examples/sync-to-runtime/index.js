// Unlike this example a typical runtime would contain the server and require the handler
// This runtime inefficiently re-requires the handler on every request

// Must be the js file, not the folder, for require.cache deletion to work
const HANDLER = './my-handler/index.js';

const http = require('http');
const server = http.createServer((req, res) => {
  delete require.cache[require.resolve(HANDLER)];
  require(HANDLER)().then(response => {
    res.writeHead(200, { 'Content-Type': 'text/plain' });
    res.end(response);
  });
});

server.listen(8080, '0.0.0.0');
