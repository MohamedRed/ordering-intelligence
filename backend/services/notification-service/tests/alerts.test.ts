import { listAlerts, storeAlert, type StoredAlert } from "../src/alerts";

const makeFirestore = () => {
  const store = new Map<string, StoredAlert>();
  return {
    store,
    collection: () => ({
      doc: (id: string) => ({
        set: async (data: StoredAlert) => store.set(id, data)
      }),
      orderBy: () => ({
        limit: () => ({
          get: async () => ({
            docs: Array.from(store.entries()).map(([id, data]) => ({
              id,
              data: () => data
            }))
          })
        })
      })
    })
  };
};

describe("alerts helpers", () => {
  it("storeAlert persists data", async () => {
    const firestore = makeFirestore() as any;
    const alert: StoredAlert = {
      id: "a1",
      title: "t",
      body: "b",
      severity: "info",
      createdAt: "2024-01-01T00:00:00Z",
      expireAt: "2024-01-02T00:00:00Z"
    };
    await storeAlert(firestore, alert);
    expect(firestore.store.get("a1")).toEqual(alert);
  });

  it("listAlerts maps id field correctly", async () => {
    const firestore = makeFirestore() as any;
    await storeAlert(firestore, {
      id: "a2",
      title: "Title",
      body: "Body",
      severity: "warning",
      createdAt: "2024-01-01T00:00:00Z",
      expireAt: "2024-01-02T00:00:00Z"
    });
    const alerts = await listAlerts(firestore, 10);
    expect(alerts).toHaveLength(1);
    expect(alerts[0].id).toBe("a2");
    expect(alerts[0].title).toBe("Title");
  });
});
