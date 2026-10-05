// Loaded with `node --require` by scripts/test-ai-usage.js ahead of the
// shipped usage helper, so the helper's real entry point can run with an
// unexpired planted token and still reach no network. Every HTTP or HTTPS
// request is recorded to the file $AI_USAGE_REQUESTS as one JSON line,
// { url, method }, and fails at once; every socket, TLS connection and name
// lookup throws before it starts.
"use strict";
const fs = require("node:fs");
const net = require("node:net");
const tls = require("node:tls");
const dns = require("node:dns");
const { EventEmitter } = require("node:events");

const refuse = () => { throw new Error("no-network: refused"); };
for (const mod of [require("node:http"), require("node:https")]) {
    mod.request = (url, options) => {
        fs.appendFileSync(process.env.AI_USAGE_REQUESTS, JSON.stringify({ url: String(url), method: options.method }) + "\n");
        const request = new EventEmitter();
        request.end = () => setImmediate(() => request.emit("error", new Error("no-network: refused")));
        request.destroy = () => {};
        return request;
    };
    mod.get = refuse;
}
net.connect = net.createConnection = tls.connect = refuse;
net.Socket.prototype.connect = refuse;
dns.lookup = refuse;
