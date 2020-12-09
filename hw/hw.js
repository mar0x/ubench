#!/usr/bin/env node

if (process.env.NXT_UNIT_INIT) {
  http = require('unit-http')
} else {
  http = require('http')
}

const body_1m = Buffer.alloc(1024 * 1024, 'Hello, world!\n');
const body_14 = body_1m.slice(0, 14);
const body_def = {
    '/':    body_1m.slice(0, 14),
    '/1k':  body_1m.slice(0, 1024),
    '/4k':  body_1m.slice(0, 1024 * 4),
    '/16k': body_1m.slice(0, 1024 * 16),
    '/64k': body_1m.slice(0, 1024 * 64),
    '/1m':  body_1m.slice(0, 1024 * 1024),
};

http.createServer(function (req, res) {
    let body = body_def[req.url] || body_14;

    res.setHeader('Content-Length', body.length);
    res.setHeader('Content-Type', 'text/plain');
    res.writeHead(200, {}).end(body);
}).listen(8003);
