import dotenv from "dotenv";

dotenv.config();

export interface ServiceConfig {
  environment: string;
  port: number;
  orderServiceUrl: string;
}

function required(key: string, fallback?: string): string {
  const value = process.env[key] ?? fallback;
  if (!value) {
    throw new Error(`Missing required configuration: ${key}`);
  }
  return value;
}

export function loadConfig(): ServiceConfig {
  return {
    environment: required("ENVIRONMENT", "dev"),
    port: Number(required("PORT", "8080")),
    orderServiceUrl: required("ORDER_SERVICE_URL")
  };
}
