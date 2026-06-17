import { decodePubSubJson } from "../src/pubsub_envelope";

describe("decodePubSubJson", () => {
  it("decodes JSON payloads from Pub/Sub message data", () => {
    const data = Buffer.from(JSON.stringify({ kind: "order_created" })).toString("base64");

    const result = decodePubSubJson<{ kind: string }>({
      message: { data, messageId: "message-1" },
      subscription: "orders-sub"
    });

    expect(result).toEqual({
      ok: true,
      value: { kind: "order_created" },
      messageId: "message-1",
      subscription: "orders-sub"
    });
  });

  it("flags missing message data", () => {
    const result = decodePubSubJson({});

    expect(result).toEqual({
      ok: false,
      reason: "missing_data"
    });
  });

  it("flags invalid JSON after base64 decoding", () => {
    const data = Buffer.from("{").toString("base64");

    const result = decodePubSubJson({ message: { data, messageId: "message-2" } });

    expect(result).toMatchObject({
      ok: false,
      reason: "invalid_json",
      messageId: "message-2"
    });
  });
});
