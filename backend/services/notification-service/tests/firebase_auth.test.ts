import express from "express";
import request from "supertest";
import { requireFirebaseAdmin, requireFirebaseUser } from "../src/firebase_auth";

function makeApp(verifier: { verifyIdToken: jest.Mock }, adminOnly = false) {
  const app = express();
  app.get("/protected", adminOnly ? requireFirebaseAdmin(verifier as any) : requireFirebaseUser(verifier as any), (req, res) => {
    res.status(200).json({ uid: (req as any).uid ?? null });
  });
  return app;
}

describe("firebase auth middleware", () => {
  it("rejects missing bearer tokens", async () => {
    const verifier = { verifyIdToken: jest.fn() };
    const res = await request(makeApp(verifier)).get("/protected");

    expect(res.status).toBe(401);
    expect(res.body).toEqual({ error: "missing_auth" });
    expect(verifier.verifyIdToken).not.toHaveBeenCalled();
  });

  it("stores decoded user id on authenticated requests", async () => {
    const verifier = { verifyIdToken: jest.fn(async () => ({ uid: "user-1" })) };
    const res = await request(makeApp(verifier)).get("/protected").set("Authorization", "Bearer token-1");

    expect(res.status).toBe(200);
    expect(res.body).toEqual({ uid: "user-1" });
    expect(verifier.verifyIdToken).toHaveBeenCalledWith("token-1");
  });

  it("allows admin tokens without a role claim", async () => {
    const verifier = { verifyIdToken: jest.fn(async () => ({ uid: "admin-1" })) };
    const res = await request(makeApp(verifier, true)).get("/protected").set("Authorization", "Bearer token-2");

    expect(res.status).toBe(200);
  });

  it("rejects non-admin role claims on admin routes", async () => {
    const verifier = { verifyIdToken: jest.fn(async () => ({ uid: "user-1", role: "staff" })) };
    const res = await request(makeApp(verifier, true)).get("/protected").set("Authorization", "Bearer token-3");

    expect(res.status).toBe(403);
    expect(res.body).toEqual({ error: "forbidden" });
  });
});
