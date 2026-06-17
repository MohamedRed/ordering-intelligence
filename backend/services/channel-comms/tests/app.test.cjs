const assert = require("node:assert/strict");
const { test } = require("node:test");

const { config, postJson, pubSubEnvelope, startApp } = require("./test_helpers.cjs");

test("health endpoint reports service metadata", async (t) => {
  const service = await startApp(config());
  t.after(service.close);

  const res = await fetch(`${service.url}/healthz`);
  assert.equal(res.status, 200);
  assert.deepEqual(await res.json(), {
    status: "ok",
    service: "channel-comms",
    environment: "test",
  });
});

test("invalid Pub/Sub payloads are acknowledged and ignored", async (t) => {
  const service = await startApp(config());
  t.after(service.close);

  const res = await postJson(`${service.url}/events/orders`, {
    message: { data: "not-json" },
  });

  assert.equal(res.status, 200);
  assert.deepEqual(await res.json(), { status: "ignored" });
});

test("orders without a new status do not call channel APIs", async (t) => {
  const service = await startApp(config());
  t.after(service.close);

  const res = await postJson(
    `${service.url}/events/orders`,
    pubSubEnvelope({
      order: {
        id: "order-1",
        channelContact: { channel: "telegram", userId: "123" },
      },
    })
  );

  assert.equal(res.status, 200);
  assert.deepEqual(await res.json(), { status: "no_status_change" });
});
