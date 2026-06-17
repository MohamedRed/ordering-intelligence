const assert = require("node:assert/strict");
const { test } = require("node:test");

const { config, postJson, readJsonBody, startApp, startServer } = require("./test_helpers.cjs");

test("Discord order updates create a DM and send the status message", async (t) => {
  const discordRequests = [];
  const discordApi = await startServer(async (req, res) => {
    const body = await readJsonBody(req);
    discordRequests.push({
      method: req.method,
      url: req.url,
      authorization: req.headers.authorization,
      body,
    });

    if (req.method === "POST" && req.url === "/users/@me/channels") {
      res.writeHead(200, { "content-type": "application/json" });
      res.end(JSON.stringify({ id: "dm-channel-1" }));
      return;
    }
    if (req.method === "POST" && req.url === "/channels/dm-channel-1/messages") {
      res.writeHead(200, { "content-type": "application/json" });
      res.end(JSON.stringify({ id: "message-1" }));
      return;
    }

    res.writeHead(404, { "content-type": "application/json" });
    res.end(JSON.stringify({ error: "not found" }));
  });
  t.after(discordApi.close);

  const service = await startApp(
    config({
      DISCORD_BOT_TOKEN: "discord-token",
      DISCORD_API_BASE_URL: discordApi.url,
    })
  );
  t.after(service.close);

  const res = await postJson(`${service.url}/events/orders`, {
    order: {
      id: "order-3",
      displayNumber: "B44",
      statusChange: { newStatus: "out_for_delivery" },
      channelContact: {
        channel: "discord_webapp",
        userId: "98765",
      },
    },
  });

  assert.equal(res.status, 200);
  assert.deepEqual(await res.json(), { status: "ok" });
  assert.equal(discordRequests.length, 2);
  assert.equal(discordRequests[0].url, "/users/@me/channels");
  assert.equal(discordRequests[0].authorization, "Bot discord-token");
  assert.deepEqual(discordRequests[0].body, { recipient_id: "98765" });
  assert.equal(discordRequests[1].url, "/channels/dm-channel-1/messages");
  assert.equal(discordRequests[1].authorization, "Bot discord-token");
  assert.deepEqual(discordRequests[1].body, {
    content: "Order #B44 is now out_for_delivery.",
  });
});
