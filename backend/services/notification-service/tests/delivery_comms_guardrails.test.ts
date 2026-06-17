import { shouldSendDeliveryComms } from "../src/delivery_comms_guardrails";

type MockFirestoreOptions = {
  eventExists?: boolean;
  stateData?: Record<string, unknown>;
  rejectTransaction?: boolean;
};

function makeFirestore(options: MockFirestoreOptions = {}) {
  const eventRef = { path: "event" };
  const stateRef = { path: "state" };
  const create = jest.fn();
  const set = jest.fn();
  const tx = {
    get: jest.fn(async (ref: unknown) => {
      if (ref === eventRef) {
        return { exists: Boolean(options.eventExists), data: () => ({}) };
      }
      return {
        exists: options.stateData !== undefined,
        data: () => options.stateData
      };
    }),
    create,
    set
  };
  const storeRef = {
    collection: jest.fn((name: string) => ({
      doc: jest.fn(() => (name === "delivery_comms_events" ? eventRef : stateRef))
    }))
  };
  const firestore = {
    collection: jest.fn(() => ({ doc: jest.fn(() => storeRef) })),
    runTransaction: jest.fn(async (handler: (transaction: typeof tx) => Promise<boolean>) => {
      if (options.rejectTransaction) {
        throw new Error("transaction unavailable");
      }
      return handler(tx);
    })
  };

  return { firestore: firestore as any, tx, create, set };
}

describe("shouldSendDeliveryComms", () => {
  const now = 1_700_000_000_000;

  beforeEach(() => {
    jest.spyOn(Date, "now").mockReturnValue(now);
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  it("allows events without an order id because idempotency cannot be keyed", async () => {
    const { firestore } = makeFirestore();

    await expect(shouldSendDeliveryComms(firestore, {
      storeId: "store-1",
      eventKey: "arriving_soon"
    })).resolves.toBe(true);

    expect(firestore.runTransaction).not.toHaveBeenCalled();
  });

  it("records the event and rate-limit state when allowed", async () => {
    const { firestore, create, set } = makeFirestore();

    await expect(shouldSendDeliveryComms(firestore, {
      storeId: "store-1",
      orderId: "order-1",
      eventKey: "arriving_soon",
      comms: { rate_limit_per_hour: 2 }
    })).resolves.toBe(true);

    expect(create).toHaveBeenCalledWith(expect.anything(), expect.objectContaining({
      storeId: "store-1",
      orderId: "order-1",
      eventKey: "arriving_soon",
      eventVersion: "v1"
    }));
    expect(set).toHaveBeenCalledWith(expect.anything(), expect.objectContaining({
      orderId: "order-1",
      count: 1,
      windowStart: new Date(now),
      updatedAt: new Date(now)
    }), { merge: true });
  });

  it("blocks duplicate delivery comms events", async () => {
    const { firestore, create, set } = makeFirestore({ eventExists: true });

    await expect(shouldSendDeliveryComms(firestore, {
      storeId: "store-1",
      orderId: "order-1",
      eventKey: "arriving_soon"
    })).resolves.toBe(false);

    expect(create).not.toHaveBeenCalled();
    expect(set).not.toHaveBeenCalled();
  });

  it("blocks events once the hourly rate limit is exhausted", async () => {
    const { firestore, create, set } = makeFirestore({
      stateData: {
        count: 1,
        windowStart: new Date(now - 1_000)
      }
    });

    await expect(shouldSendDeliveryComms(firestore, {
      storeId: "store-1",
      orderId: "order-1",
      eventKey: "arriving_soon",
      comms: { rate_limit_per_hour: 1 }
    })).resolves.toBe(false);

    expect(create).not.toHaveBeenCalled();
    expect(set).not.toHaveBeenCalled();
  });

  it("fails closed when the guardrail transaction cannot complete", async () => {
    const { firestore } = makeFirestore({ rejectTransaction: true });
    const warn = jest.spyOn(console, "warn").mockImplementation(() => undefined);

    await expect(shouldSendDeliveryComms(firestore, {
      storeId: "store-1",
      orderId: "order-1",
      eventKey: "arriving_soon"
    })).resolves.toBe(false);

    expect(warn).toHaveBeenCalledWith(expect.stringContaining("delivery_comms_guardrails_failed"));
  });
});
