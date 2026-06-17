import type { NextFunction, Request, RequestHandler, Response } from "express";
import type { Auth } from "firebase-admin/auth";

type TokenVerifier = Pick<Auth, "verifyIdToken">;

function bearerToken(req: Request): string | undefined {
  const authHeader = req.header("Authorization");
  if (!authHeader || !authHeader.startsWith("Bearer ")) {
    return undefined;
  }
  const token = authHeader.replace("Bearer ", "").trim();
  return token || undefined;
}

export function requireFirebaseAdmin(firebaseAuth: TokenVerifier): RequestHandler {
  return async (req: Request, res: Response, next: NextFunction) => {
    try {
      const token = bearerToken(req);
      if (!token) {
        return res.status(401).json({ error: "missing_auth" });
      }
      const decoded = await firebaseAuth.verifyIdToken(token);
      if (decoded.role && decoded.role !== "admin") {
        return res.status(403).json({ error: "forbidden" });
      }
      return next();
    } catch (err) {
      console.error("auth failed", err);
      return res.status(401).json({ error: "unauthorized" });
    }
  };
}

export function requireFirebaseUser(firebaseAuth: TokenVerifier): RequestHandler {
  return async (req: Request, res: Response, next: NextFunction) => {
    try {
      const token = bearerToken(req);
      if (!token) {
        return res.status(401).json({ error: "missing_auth" });
      }
      const decoded = await firebaseAuth.verifyIdToken(token);
      (req as any).uid = decoded.uid;
      return next();
    } catch (err) {
      console.error("auth failed", err);
      return res.status(401).json({ error: "unauthorized" });
    }
  };
}
