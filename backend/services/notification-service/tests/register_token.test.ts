import { registerToken, type DeviceToken } from "../src/registerToken";

// Mock Firestore with an in-memory map
const makeFirestore = () => {
  const store = new Map<string, any>();
  return {
    store,
    collection: () => ({
      doc: (id: string) => ({
        set: async (data: any) => store.set(id, data)
      })
    })
  };
};

describe("registerToken", () => {
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
});
