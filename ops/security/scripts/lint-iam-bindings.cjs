#!/usr/bin/env node
const { readdir, readFile, stat } = require("node:fs/promises");
const path = require("node:path");

const repoRoot = path.resolve(__dirname, "../../..");
const terraformRoot = path.join(repoRoot, "infrastructure/terraform");
const forbiddenRoles = new Set(["roles/editor", "roles/owner"]);

const errors = [];

async function walk(directory) {
  const entries = await readdir(directory, { withFileTypes: true });
  const tasks = entries.map(async (entry) => {
    const fullPath = path.join(directory, entry.name);
    if (entry.isDirectory()) {
      return walk(fullPath);
    }
    if (entry.isFile() && entry.name.endsWith(".tf")) {
      await inspectFile(fullPath);
    }
  });
  await Promise.all(tasks);
}

async function inspectFile(filePath) {
  const contents = await readFile(filePath, "utf8");
  const lines = contents.split(/\r?\n/);
  lines.forEach((line, index) => {
    for (const role of forbiddenRoles) {
      if (line.includes(role)) {
        errors.push(`${path.relative(repoRoot, filePath)}:${index + 1} -> contains ${role}`);
      }
    }
  });
}

async function main() {
  try {
    const stats = await stat(terraformRoot);
    if (!stats.isDirectory()) {
      throw new Error(`${terraformRoot} is not a directory`);
    }
  } catch (error) {
    console.error(`Unable to access Terraform root: ${error.message}`);
    process.exit(1);
  }

  await walk(terraformRoot);

  if (errors.length > 0) {
    console.error("Forbidden IAM roles detected in Terraform configuration:");
    errors.forEach((message) => console.error(` • ${message}`));
    process.exit(1);
  }

  console.log("IAM binding lint passed (no editor/owner roles found).");
}

main().catch((error) => {
  console.error(`IAM lint failed: ${error.message}`);
  process.exit(1);
});
