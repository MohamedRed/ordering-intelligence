const assert = require("node:assert/strict");
const { test } = require("node:test");

const {
  config,
  postJson,
  pubSubEnvelope,
  readJsonBody,
  startApp,
  startServer,
} = require("./test_helpers.cjs");

test("Telegram order updates are sent from Pub/Sub push envelopes", async (t) => {
  const telegramRequests = [];
  const telegramApi = await startServer(async (req, res) => {
    telegramRequests.push({
      method: req.method,
      url: req.url,
      body: await readJsonBody(req),
    });
    res.writeHead(200, { "content-type": "application/json" });
    res.end(JSON.stringify({ ok: true, result: { message_id: 1 } }));
  });
  t.after(telegramApi.close);

  const service = await startApp(
    config({
      TELEGRAM_BOT_TOKEN: "telegram-token",
      TELEGRAM_API_BASE_URL: telegramApi.url,
    })
  );
  t.after(service.close);

  const res = await postJson(
    `${service.url}/events/orders`,
    pubSubEnvelope({
      order: {
        id: "order-2",
        displayNumber: "A12",
        customerName: "Sam",
        statusChange: {
          previousStatus: "accepted",
          newStatus: "ready",
          note: "Pick up at the counter",
        },
        channelContact: {
          channel: "telegram_webapp",
          userId: "12345",
          threadId: "456",
        },
      },
    })
  );

  assert.equal(res.status, 200);
  assert.deepEqual(await res.json(), { status: "ok" });
  assert.equal(telegramRequests.length, 1);
  assert.equal(telegramRequests[0].method, "POST");
  assert.equal(telegramRequests[0].url, "/bottelegram-token/sendMessage");
  assert.deepEqual(telegramRequests[0].body, {
    chat_id: "12345",
    text: "Order #A12, Sam is now ready.\nNote: Pick up at the counter",
    message_thread_id: 456,
  });
});
