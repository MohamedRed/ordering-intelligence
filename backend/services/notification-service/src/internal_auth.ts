import { NextFunction, Request, RequestHandler, Response } from "express";
import { OAuth2Client } from "google-auth-library";

export type OidcAuthConfig = {
  audience?: string;
  allowedEmails?: string;
};

type OidcTokenPayload = {
  email?: string;
};

const oidcVerifier = new OAuth2Client();

export function parseAllowedEmails(value?: string): string[] {
  if (!value) return [];
  return value
    .split(",")
    .map((entry) => entry.trim())
    .filter(Boolean);
}

export async function requireGoogleOidcRequest(
  req: Request,
  res: Response,
  auth: OidcAuthConfig
): Promise<boolean> {
  const audience = String(auth.audience ?? "").trim();
  const allowedEmails = parseAllowedEmails(auth.allowedEmails);
  if (!audience || allowedEmails.length === 0) {
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
    const payload = (ticket.getPayload() ?? {}) as OidcTokenPayload;
    const email = String(payload.email ?? "").trim();
    const allowed = allowedEmails.some((entry) => entry.toLowerCase() === email.toLowerCase());
    if (!email || !allowed) {
      res.status(401).json({ error: "unauthorized" });
      return false;
    }
    return true;
  } catch (err) {
    console.warn(
      JSON.stringify({
        level: "warn",
        event: "oidc_verify_failed",
        audience,
        message: (err as Error).message
      })
    );
    res.status(401).json({ error: "unauthorized" });
    return false;
  }
}

export function requireGoogleOidc(auth: OidcAuthConfig): RequestHandler {
  return async (req: Request, res: Response, next: NextFunction) => {
    if (await requireGoogleOidcRequest(req, res, auth)) {
      next();
    }
  };
}
