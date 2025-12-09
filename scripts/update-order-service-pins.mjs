#!/usr/bin/env node
import { execSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import tls from "node:tls";
import { fileURLToPath } from "node:url";
import { createHash } from "node:crypto";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(__dirname, "..");

const ENVIRONMENTS = [
  {
    name: "staging",
    terraformDir: path.join(
      repoRoot,
      "infrastructure/terraform/environments/staging"
    )
  },
  {
    name: "prod",
    terraformDir: path.join(
      repoRoot,
      "infrastructure/terraform/environments/prod"
    )
  }
];

const PIN_FILES = [
  path.join(
    repoRoot,
    "apps/business/lib/bootstrap/pins.dart"
  ),
  path.join(
    repoRoot,
    "apps/admin/lib/bootstrap/pins.dart"
  )
];

function parseArgs() {
  const envArg = process.argv.find((arg) => arg.startsWith("--env="));
  if (!envArg) {
    return ENVIRONMENTS;
  }
  const values = envArg.replace("--env=", "").split(",");
  return ENVIRONMENTS.filter((env) => values.includes(env.name));
}

function terraformOutput(env, outputName) {
  return execSync(`terraform output -raw ${outputName}`, {
    cwd: env.terraformDir,
    stdio: ["ignore", "pipe", "inherit"]
  })
    .toString()
    .trim();
}

function fetchFingerprint(host) {
  return new Promise((resolve) => {
    const socket = tls.connect(
      {
        host,
        port: 443,
        servername: host,
        rejectUnauthorized: false
      },
      () => {
        try {
          const cert = socket.getPeerCertificate(true);
          if (!cert || !cert.raw) {
            console.warn(`No certificate presented by ${host}`);
            resolve(null);
            socket.end();
            return;
          }
          const fingerprint = createHash("sha256")
            .update(cert.raw)
            .digest("hex");
          resolve(fingerprint);
        } catch (error) {
          console.warn(`Failed to compute fingerprint for ${host}: ${error}`);
          resolve(null);
        } finally {
          socket.end();
        }
      }
    );

    socket.on("error", (error) => {
      console.warn(`TLS error contacting ${host}: ${error.message}`);
      resolve(null);
    });

    socket.setTimeout(10000, () => {
      console.warn(`Timeout fetching certificate from ${host}`);
      socket.destroy();
      resolve(null);
    });
  });
}

function escapeForRegex(text) {
  return text.replace(/[-/\\^$*+?.()|[\]{}]/g, "\\$&");
}

function updatePinsFile(filePath, replacements) {
  let content = fs.readFileSync(filePath, "utf8");
  let updated = false;

  for (const [host, fingerprint] of Object.entries(replacements)) {
    if (!fingerprint) {
      continue;
    }
    const regex = new RegExp(
      `('${escapeForRegex(host)}'\\s*:\\s*)'[^']*'`,
      "g"
    );
    if (regex.test(content)) {
      content = content.replace(regex, `$1'${fingerprint}'`);
      updated = true;
    }
  }

  if (updated) {
    fs.writeFileSync(filePath, content);
    console.log(`Updated pins in ${path.relative(repoRoot, filePath)}`);
  } else {
    console.warn(
      `No matching hosts found in ${path.relative(repoRoot, filePath)}`
    );
  }
}

async function main() {
  const environments = parseArgs();
  const fingerprints = {};

  for (const env of environments) {
    console.log(`\nFetching load balancer hostname for ${env.name}...`);
    const host = terraformOutput(env, "order_service_lb_hostname");
    console.log(`  Hostname: ${host}`);
    const fingerprint = await fetchFingerprint(host);
    if (!fingerprint) {
      console.warn(
        `  Unable to retrieve fingerprint for ${host}. Certificate may still be provisioning.`
      );
      continue;
    }
    fingerprints[host] = fingerprint;
    console.log(`  SHA256 fingerprint: ${fingerprint}`);
  }

  if (Object.keys(fingerprints).length === 0) {
    console.warn("No fingerprints retrieved; skipping pin updates.");
    return;
  }

  PIN_FILES.forEach((filePath) => updatePinsFile(filePath, fingerprints));
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
