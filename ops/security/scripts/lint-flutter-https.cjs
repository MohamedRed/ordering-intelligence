#!/usr/bin/env node
const { readdir, stat, readFile } = require("node:fs/promises");
const path = require("node:path");

const repoRoot = path.resolve(__dirname, "../../..");
const appsRoot = path.join(repoRoot, "apps");
const ignoredDirs = new Set(["build", ".dart_tool"]);
const forbiddenPatterns = [
  { regex: /http:\/\//i, message: "raw http:// URL" },
  { regex: /\bUri\.http\b/, message: "Uri.http constructor" }
];

const violations = [];

async function walk(directory) {
  const entries = await readdir(directory, { withFileTypes: true });
  await Promise.all(
    entries.map(async (entry) => {
      const fullPath = path.join(directory, entry.name);
      if (entry.isDirectory()) {
        if (!ignoredDirs.has(entry.name)) {
          await walk(fullPath);
        }
        return;
      }
      if (entry.isFile() && entry.name.endsWith(".dart")) {
        await inspectFile(fullPath);
      }
    })
  );
}

async function inspectFile(filePath) {
  const contents = await readFile(filePath, "utf8");
  const lines = contents.split(/\r?\n/);
  lines.forEach((line, index) => {
    forbiddenPatterns.forEach(({ regex, message }) => {
      if (regex.test(line)) {
        violations.push(
          `${path.relative(repoRoot, filePath)}:${index + 1} -> ${message} detected`
        );
      }
    });
  });
}

async function main() {
  try {
    const stats = await stat(appsRoot);
    if (!stats.isDirectory()) {
      throw new Error(`${appsRoot} is not a directory`);
    }
  } catch (error) {
    console.error(`Unable to access Flutter apps: ${error.message}`);
    process.exit(1);
  }

  await walk(appsRoot);

  if (violations.length > 0) {
    console.error("HTTPS lint failed. Update the code to avoid plain HTTP usage:");
    violations.forEach((line) => console.error(` • ${line}`));
    process.exit(1);
  }

  console.log("Flutter HTTPS lint passed (no http:// or Uri.http detected).");
}

main().catch((error) => {
  console.error(`Flutter HTTPS lint crashed: ${error.message}`);
  process.exit(1);
});
