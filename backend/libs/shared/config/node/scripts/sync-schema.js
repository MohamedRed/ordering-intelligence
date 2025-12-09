#!/usr/bin/env node

const fs = require("fs");
const path = require("path");

const sourcePath = path.resolve(__dirname, "..", "..", "schema", "schema.json");
const targetPath = path.resolve(__dirname, "..", "schema", "schema.json");

function copySchema() {
  if (!fs.existsSync(sourcePath)) {
    console.warn(`[config] Skipping schema sync, source missing at ${sourcePath}`);
    return;
  }

  fs.mkdirSync(path.dirname(targetPath), { recursive: true });
  fs.copyFileSync(sourcePath, targetPath);
}

try {
  copySchema();
} catch (error) {
  console.error(`[config] Failed to copy schema: ${error.message}`);
  process.exitCode = 1;
}
