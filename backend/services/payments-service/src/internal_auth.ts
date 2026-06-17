import { NextFunction, Request, RequestHandler, Response } from "express";
import { OAuth2Client } from "google-auth-library";
import { PaymentsConfig } from "./config";

const oidcVerifier = new OAuth2Client();

type InternalTokenPayload = {
  email?: string;
};

export const parseAllowedEmails = (value?: string): string[] => {
  if (!value) return [];
  return value
    .split(",")
    .map((entry) => entry.trim())
    .filter((entry) => entry.length > 0);
};

export function isPublicPaymentsPath(pathname: string): boolean {
  const normalized = pathname.replace(/\/+$/, "") || "/";
  return normalized === "/healthz" || normalized === "/webhooks/stripe";
}

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
  const allowedEmails = parseAllowedEmails(config.INTERNAL_ALLOWED_EMAILS);
  if (allowedEmails.length === 0) {
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
    const allowed = allowedEmails.some((entry) => entry.toLowerCase() === email.toLowerCase());
    if (!allowed) {
      res.status(401).json({ error: "unauthorized" });
      return false;
    }
    return true;
  } catch (err) {
    res.status(401).json({ error: "unauthorized" });
    return false;
  }
}

export function requirePaymentsInternalAuth(config: PaymentsConfig): RequestHandler {
  return async (req: Request, res: Response, next: NextFunction) => {
    if (req.method === "OPTIONS" || isPublicPaymentsPath(req.path)) {
      next();
      return;
    }
    if (await requireInternalAuth(req, res, config)) {
      next();
    }
  };
}
