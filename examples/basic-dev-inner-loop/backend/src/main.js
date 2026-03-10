const http = require('http');
const { echo } = require('./utils');
const port = 3000;

const server = http.createServer((req, res) => {
  res.writeHead(200, { 'Content-Type': 'text/plain' });
  res.end(echo('Hello World!'));
});

server.listen(port, () => console.log(`Example app build ${process.env.BUILD_TAG} listening on port ${port}!`));
