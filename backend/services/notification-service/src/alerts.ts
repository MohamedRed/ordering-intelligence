import { Firestore } from "@google-cloud/firestore";

export interface StoredAlert {
  id: string;
  title: string;
  body: string;
  severity: string;
  createdAt: string;
  expireAt?: string;
}

export async function listAlerts(firestore: Firestore, limit = 100): Promise<StoredAlert[]> {
  const snapshot = await firestore
    .collection("alerts")
    .orderBy("createdAt", "desc")
    .limit(limit)
    .get();

  return snapshot.docs.map((doc) => {
    const data = doc.data() as StoredAlert;
    return { ...data, id: doc.id };
  });
}

export async function storeAlert(firestore: Firestore, alert: StoredAlert): Promise<void> {
  await firestore.collection("alerts").doc(alert.id).set(alert);
}
