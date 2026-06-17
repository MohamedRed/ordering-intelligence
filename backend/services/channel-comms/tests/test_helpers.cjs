const http = require("node:http");
const { once } = require("node:events");

const { createChannelCommsApp } = require("../dist/app");

function config(overrides = {}) {
  return {
    PORT: 0,
    ENVIRONMENT: "test",
    ...overrides,
  };
}

async function startServer(listener) {
  const server = http.createServer(listener);
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  const address = server.address();
  if (!address || typeof address === "string") {
    throw new Error("server did not bind to a TCP port");
  }
  return {
    url: `http://127.0.0.1:${address.port}`,
    close: () =>
      new Promise((resolve, reject) => {
        server.close((err) => (err ? reject(err) : resolve()));
      }),
  };
}

async function startApp(appConfig) {
  return startServer(createChannelCommsApp(appConfig));
}

async function readJsonBody(req) {
  const chunks = [];
  for await (const chunk of req) {
    chunks.push(Buffer.from(chunk));
  }
  const raw = Buffer.concat(chunks).toString("utf8");
  return raw ? JSON.parse(raw) : {};
}

async function postJson(url, body) {
  return fetch(url, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  });
}

function pubSubEnvelope(payload) {
  return {
    message: {
      data: Buffer.from(JSON.stringify(payload), "utf8").toString("base64"),
    },
  };
}

module.exports = {
  config,
  postJson,
  pubSubEnvelope,
  readJsonBody,
  startApp,
  startServer,
};
