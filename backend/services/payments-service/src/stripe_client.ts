import Stripe from "stripe";

export const STRIPE_API_VERSION = "2025-02-24.acacia";

export function buildStripe(secretKey?: string): Stripe {
  if (!secretKey) {
    throw new Error("STRIPE_SECRET_KEY missing");
  }
  return new Stripe(secretKey, { apiVersion: STRIPE_API_VERSION });
}
