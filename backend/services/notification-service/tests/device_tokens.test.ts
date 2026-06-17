import {
  listDeviceTokensForCustomer,
  listDeviceTokensForUser,
  registerToken,
  type DeviceToken
} from "../src/device_tokens";

function makeFirestore() {
  const store = new Map<string, any>();
  const makeQuery = () => {
    const filters: Array<{ field: string; value: string }> = [];
    const query = {
      doc: (id: string) => ({
        set: async (data: any) => store.set(id, data)
      }),
      where: (field: string, _op: string, value: string) => {
        filters.push({ field, value });
        return query;
      },
      get: async () => ({
        docs: Array.from(store.entries())
          .filter(([, data]) => filters.every((filter) => data?.[filter.field] === filter.value))
          .map(([id]) => ({ id }))
      })
    };
    return query;
  };

  return {
    store,
    collection: () => makeQuery()
  };
}

describe("device token storage", () => {
  it("stores device tokens keyed by token", async () => {
    const firestore = makeFirestore() as any;
    const payload: DeviceToken = {
      token: "tok1",
      userId: "user1",
      storeId: "store1",
      platform: "ios",
      updatedAt: new Date().toISOString()
    };

    await registerToken(firestore, payload);

    expect(firestore.store.get("tok1")).toEqual(payload);
  });

  it("lists tokens by user and store", async () => {
    const firestore = makeFirestore() as any;
    firestore.store.set("tok1", { userId: "driver-1", storeId: "store-1" });
    firestore.store.set("tok2", { userId: "driver-1", storeId: "store-2" });
    firestore.store.set("tok3", { userId: "driver-2", storeId: "store-1" });

    await expect(listDeviceTokensForUser(firestore, {
      userId: "driver-1",
      storeId: "store-1"
    })).resolves.toEqual(["tok1"]);
  });

  it("lists tokens by customer and store", async () => {
    const firestore = makeFirestore() as any;
    firestore.store.set("tok1", { customerId: "customer-1", storeId: "store-1" });
    firestore.store.set("tok2", { customerId: "customer-1", storeId: "store-2" });
    firestore.store.set("tok3", { customerId: "customer-2", storeId: "store-1" });

    await expect(listDeviceTokensForCustomer(firestore, {
      customerId: "customer-1",
      storeId: "store-1"
    })).resolves.toEqual(["tok1"]);
  });

  it("returns no tokens for blank lookup identifiers", async () => {
    const firestore = makeFirestore() as any;

    await expect(listDeviceTokensForUser(firestore, { userId: " " })).resolves.toEqual([]);
    await expect(listDeviceTokensForCustomer(firestore, { customerId: " " })).resolves.toEqual([]);
  });
});
