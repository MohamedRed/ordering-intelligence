"use strict";

const fs = require("fs");
const path = require("path");

function loadSchema() {
  const candidatePaths = [
    path.join(__dirname, "schema", "schema.json"),
    path.join(__dirname, "..", "schema", "schema.json")
  ];

  for (const candidate of candidatePaths) {
    try {
      const contents = fs.readFileSync(candidate, "utf8");
      return JSON.parse(contents);
    } catch (error) {
      if (error.code !== "ENOENT") {
        throw new Error(`Failed to load configuration schema from "${candidate}": ${error.message}`);
      }
    }
  }

  throw new Error(
    `Unable to locate configuration schema. Checked: ${candidatePaths
      .map((candidate) => `"${candidate}"`)
      .join(", ")}`
  );
}

const schema = loadSchema();

const TYPE_CASTERS = {
  string: (value) => value,
  number: (value) => {
    if (value === "" || value === undefined) return undefined;
    const parsed = Number(value);
    if (Number.isNaN(parsed)) {
      throw new Error(`Expected number but received "${value}"`);
    }
    return parsed;
  },
  boolean: (value) => {
    if (typeof value === "boolean") return value;
    if (value === undefined) return undefined;
    const normalized = String(value).toLowerCase();
    if (["true", "1", "yes", "y"].includes(normalized)) {
      return true;
    }
    if (["false", "0", "no", "n"].includes(normalized)) {
      return false;
    }
    throw new Error(`Expected boolean but received "${value}"`);
  }
};

function loadConfig(serviceName, options = {}) {
  if (!serviceName) {
    throw new Error("Service name is required to load configuration.");
  }

  const serviceSchema = schema[serviceName];
  if (!serviceSchema) {
    throw new Error(`No configuration schema found for service "${serviceName}".`);
  }

  const sourceEnv = options.env ?? process.env;
  const errors = [];
  const config = {};

  for (const [key, definition] of Object.entries(serviceSchema)) {
    const envKey = definition.env ?? key;
    const rawValue = sourceEnv[envKey];
    const caster = TYPE_CASTERS[definition.type];

    if (!caster) {
      errors.push(`Unsupported type "${definition.type}" for ${key}.`);
      continue;
    }

    try {
      let value = caster(rawValue);
      if (value === undefined || value === null) {
        if (definition.default !== undefined) {
          value = definition.default;
        } else if (definition.required) {
          errors.push(`Missing required configuration value "${envKey}".`);
          continue;
        }
      }
      config[key] = value;
    } catch (error) {
      errors.push(`${envKey}: ${error.message}`);
    }
  }

  if (errors.length > 0) {
    throw new Error(
      `Configuration validation failed for service "${serviceName}":\n - ${errors.join("\n - ")}`
    );
  }

  return config;
}

function getSchema() {
  return schema;
}

module.exports = {
  loadConfig,
  getSchema
};
