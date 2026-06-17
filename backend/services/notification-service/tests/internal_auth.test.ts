import { Request, Response } from "express";

const mockVerifyIdToken = jest.fn(async (_options: unknown) => ({
  getPayload: () => ({ email: "caller@example.iam.gserviceaccount.com" })
}));

jest.mock("google-auth-library", () => ({
  OAuth2Client: class {
    verifyIdToken = (options: unknown) => mockVerifyIdToken(options);
  }
}));

import { parseAllowedEmails, requireGoogleOidcRequest } from "../src/internal_auth";

function makeRequest(authHeader?: string): Request {
  return {
    header: (name: string) => (name === "Authorization" ? authHeader ?? "" : "")
  } as Request;
}

function makeResponse(): Response & { statusCode?: number; body?: unknown } {
  const res = {
    statusCode: undefined as number | undefined,
    body: undefined as unknown,
    status(code: number) {
      this.statusCode = code;
      return this;
    },
    json(payload: unknown) {
      this.body = payload;
      return this;
    }
  };
  return res as Response & { statusCode?: number; body?: unknown };
}

describe("notification internal auth", () => {
  beforeEach(() => {
    mockVerifyIdToken.mockClear();
    mockVerifyIdToken.mockResolvedValue({
      getPayload: () => ({ email: "caller@example.iam.gserviceaccount.com" })
    });
  });

  it("parses comma-separated allowlists", () => {
    expect(parseAllowedEmails("a@example.com, , B@example.com ")).toEqual([
      "a@example.com",
      "B@example.com"
    ]);
  });

  it("fails closed when config is missing", async () => {
    const res = makeResponse();
    const ok = await requireGoogleOidcRequest(makeRequest("Bearer token"), res, {
      audience: "https://notification.example.com",
      allowedEmails: ""
    });

    expect(ok).toBe(false);
    expect(res.statusCode).toBe(403);
    expect(res.body).toEqual({ error: "internal_auth_not_configured" });
    expect(mockVerifyIdToken).not.toHaveBeenCalled();
  });

  it("rejects missing bearer token", async () => {
    const res = makeResponse();
    const ok = await requireGoogleOidcRequest(makeRequest(), res, {
      audience: "https://notification.example.com",
      allowedEmails: "caller@example.iam.gserviceaccount.com"
    });

    expect(ok).toBe(false);
    expect(res.statusCode).toBe(401);
    expect(res.body).toEqual({ error: "missing_auth" });
    expect(mockVerifyIdToken).not.toHaveBeenCalled();
  });

  it("rejects callers outside the allowlist", async () => {
    const res = makeResponse();
    const ok = await requireGoogleOidcRequest(makeRequest("Bearer token"), res, {
      audience: "https://notification.example.com",
      allowedEmails: "other@example.iam.gserviceaccount.com"
    });

    expect(ok).toBe(false);
    expect(res.statusCode).toBe(401);
    expect(res.body).toEqual({ error: "unauthorized" });
  });

  it("accepts allowlisted callers", async () => {
    const res = makeResponse();
    const ok = await requireGoogleOidcRequest(makeRequest("Bearer token"), res, {
      audience: "https://notification.example.com",
      allowedEmails: "caller@example.iam.gserviceaccount.com"
    });

    expect(ok).toBe(true);
    expect(res.statusCode).toBeUndefined();
    expect(mockVerifyIdToken).toHaveBeenCalledWith({
      idToken: "token",
      audience: "https://notification.example.com"
    });
  });
});
