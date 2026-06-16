import { Request, Response } from "express";
import { OAuth2Client } from "google-auth-library";
import { PaymentsConfig } from "./config";

const oidcVerifier = new OAuth2Client();

type InternalTokenPayload = {
  email?: string;
};

const parseAllowedEmails = (value?: string): string[] => {
  if (!value) return [];
  return value
    .split(",")
    .map((entry) => entry.trim())
    .filter((entry) => entry.length > 0);
};

export async function requireInternalAuth(
  req: Request,
  res: Response,
  config: PaymentsConfig
): Promise<boolean> {
  const audience = (config.INTERNAL_AUTH_AUDIENCE || "").trim();
  if (!audience) {
    res.status(403).json({ error: "internal_auth_not_configured" });
    return false;
  }

  const authHeader = String(req.header("Authorization") ?? "");
  if (!authHeader.startsWith("Bearer ")) {
    res.status(401).json({ error: "missing_auth" });
    return false;
  }
  const token = authHeader.replace("Bearer ", "").trim();
  if (!token) {
    res.status(401).json({ error: "missing_auth" });
    return false;
  }

  try {
    const ticket = await oidcVerifier.verifyIdToken({ idToken: token, audience });
    const payload = (ticket.getPayload() ?? {}) as InternalTokenPayload;
    const email = String(payload.email ?? "").trim();
    if (!email) {
      res.status(401).json({ error: "unauthorized" });
      return false;
    }
    const allowedEmails = parseAllowedEmails(config.INTERNAL_ALLOWED_EMAILS);
    if (allowedEmails.length > 0) {
      const allowed = allowedEmails.some((entry) => entry.toLowerCase() === email.toLowerCase());
      if (!allowed) {
        res.status(401).json({ error: "unauthorized" });
        return false;
      }
    }
    return true;
  } catch (err) {
    res.status(401).json({ error: "unauthorized" });
    return false;
  }
}
