#!/usr/bin/env node
const { readFile } = require("node:fs/promises");
const path = require("node:path");
const { parseArgs } = require("node:util");
const hcl = require("hcl2-parser");

const repoRoot = path.resolve(__dirname, "../../..");
const defaultEnvRoot = path.join(repoRoot, "infrastructure/terraform/environments");

const parsedArgs = parseArgs({
  options: {
    envRoot: { type: "string" },
    envs: { type: "string" }
  }
});

const envRoot = path.resolve(parsedArgs.values.envRoot ?? defaultEnvRoot);
const envList = (parsedArgs.values.envs ?? "dev,staging,prod")
  .split(",")
  .map((value) => value.trim())
  .filter(Boolean);

const validServices = new Set([
  "order_service",
  "admin_service"
]);

const validKeys = new Set([
  "min_scale",
  "max_scale",
  "container_concurrency",
  "timeout_seconds",
  "cpu",
  "memory",
  "startup_cpu_boost",
  "env_overrides",
  "secret_env_overrides"
]);

const numericRules = {
  min_scale: { min: 0 },
  max_scale: { min: 1 },
  container_concurrency: { min: 1, max: 1000 },
  timeout_seconds: { min: 1, max: 3600 }
};

const errors = [];

function formatError(error) {
  if (error instanceof Error && error.message) {
    return error.message;
  }
  try {
    return JSON.stringify(error);
  } catch {
    return String(error);
  }
}

function isPlainObject(value) {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function assertInteger(value, key, service, envName, rule) {
  if (typeof value !== "number" || !Number.isInteger(value)) {
    errors.push(`${envName}:${service} -> ${key} must be an integer. Received ${value}`);
    return;
  }
  if (rule?.min !== undefined && value < rule.min) {
    errors.push(`${envName}:${service} -> ${key} must be >= ${rule.min}. Received ${value}`);
  }
  if (rule?.max !== undefined && value > rule.max) {
    errors.push(`${envName}:${service} -> ${key} must be <= ${rule.max}. Received ${value}`);
  }
}

function assertString(value, key, service, envName, pattern) {
  if (typeof value !== "string") {
    errors.push(`${envName}:${service} -> ${key} must be a string. Received ${value}`);
    return;
  }
  if (pattern && !pattern.test(value)) {
    errors.push(`${envName}:${service} -> ${key} must match ${pattern}. Received ${value}`);
  }
}

function validateMapOfStrings(value, key, service, envName) {
  if (!isPlainObject(value)) {
    errors.push(`${envName}:${service} -> ${key} must be an object map.`);
    return;
  }
  for (const [envKey, envValue] of Object.entries(value)) {
    if (typeof envValue !== "string") {
      errors.push(
        `${envName}:${service} -> ${key}.${envKey} must be a string. Received ${envValue}`
      );
    }
  }
}

async function lintEnvironment(envName) {
  const tfvarsPath = path.join(envRoot, envName, "terraform.tfvars");
  let contents;
  try {
    contents = await readFile(tfvarsPath, "utf8");
  } catch (error) {
    errors.push(`Failed to read ${tfvarsPath}: ${formatError(error)}`);
    return;
  }

  let parsed;
  try {
    parsed = hcl.parseToObject(contents);
  } catch (error) {
    errors.push(`Failed to parse ${tfvarsPath}: ${formatError(error)}`);
    return;
  }

  const aggregate = Object.assign(
    {},
    ...parsed.filter((entry) => isPlainObject(entry))
  );
  const overrides = aggregate.cloud_run_overrides;

  if (!overrides) {
    return;
  }

  if (!isPlainObject(overrides)) {
    errors.push(`${envName}: cloud_run_overrides must be an object.`);
    return;
  }

  for (const [service, config] of Object.entries(overrides)) {
    if (!validServices.has(service)) {
      errors.push(`${envName}: ${service} is not a supported Cloud Run service.`);
    }

    if (!isPlainObject(config)) {
      errors.push(`${envName}:${service} overrides must be an object.`);
      continue;
    }

    for (const key of Object.keys(config)) {
      if (!validKeys.has(key)) {
        errors.push(`${envName}:${service} -> ${key} is not a supported override.`);
      }
    }

    for (const [key, rule] of Object.entries(numericRules)) {
      if (key in config) {
        assertInteger(config[key], key, service, envName, rule);
      }
    }

    if ("cpu" in config) {
      assertString(config.cpu, "cpu", service, envName, /^\d+(m)?$/);
    }

    if ("memory" in config) {
      assertString(config.memory, "memory", service, envName, /^\d+(Mi|Gi)$/);
    }

    if ("startup_cpu_boost" in config && typeof config.startup_cpu_boost !== "boolean") {
      errors.push(`${envName}:${service} -> startup_cpu_boost must be a boolean.`);
    }

    if ("env_overrides" in config) {
      validateMapOfStrings(config.env_overrides, "env_overrides", service, envName);
    }

    if ("secret_env_overrides" in config) {
      validateMapOfStrings(config.secret_env_overrides, "secret_env_overrides", service, envName);
    }

    if ("min_scale" in config && "max_scale" in config) {
      const min = config.min_scale;
      const max = config.max_scale;
      if (
        typeof min === "number" &&
        typeof max === "number" &&
        Number.isInteger(min) &&
        Number.isInteger(max) &&
        min > max
      ) {
        errors.push(`${envName}:${service} -> min_scale cannot exceed max_scale.`);
      }
    }
  }
}

async function main() {
  if (envList.length === 0) {
    errors.push("No environments provided to lint.");
  }

  await Promise.all(envList.map((env) => lintEnvironment(env)));

  if (errors.length > 0) {
    console.error("Cloud Run override validation failed:");
    for (const message of errors) {
      console.error(` • ${message}`);
    }
    process.exit(1);
  }

  console.log(
    `Cloud Run overrides validated for: ${
      envList.length ? envList.join(", ") : "(none)"
    }`
  );
}

main().catch((error) => {
  console.error(`Cloud Run override validator crashed: ${formatError(error)}`);
  process.exit(1);
});
