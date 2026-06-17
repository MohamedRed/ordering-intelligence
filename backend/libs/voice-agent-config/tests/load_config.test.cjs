const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { test } = require("node:test");

const {
  inferVoiceAgentEnvironment,
  loadVoiceAgentConfig,
} = require("../dist");

function withConfigDir(t, files) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "voice-agent-config-"));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  for (const [name, content] of Object.entries(files)) {
    fs.writeFileSync(path.join(dir, name), JSON.stringify(content, null, 2));
  }
  return dir;
}

function baseConfig(overrides = {}) {
  return {
    presetName: "liive-default",
    llm: {
      provider: "openai",
      model: "gpt-4o-mini",
      systemPrompt: "Take accurate food orders.",
      temperature: 0.2,
    },
    stt: {
      provider: "deepgram",
      model: "nova-3",
      language: "fr",
    },
    tts: {
      provider: "elevenlabs",
      voiceId: "voice-default",
      language: "fr",
    },
    tools: [
      {
        name: "submit_order",
        invoke: {
          method: "POST",
          url: "https://order-service.test/orders",
        },
      },
    ],
    safety: {
      confirmationPolicy: {
        requireExplicitConfirm: true,
      },
    },
    ...overrides,
  };
}

test("inferVoiceAgentEnvironment normalizes known environment aliases", () => {
  assert.equal(inferVoiceAgentEnvironment({ NODE_ENV: "production" }), "prod");
  assert.equal(inferVoiceAgentEnvironment({ ENVIRONMENT: "stage" }), "staging");
  assert.equal(inferVoiceAgentEnvironment({ APP_ENV: "local" }), "dev");
});

test("loadVoiceAgentConfig validates and loads an environment config", (t) => {
  const dir = withConfigDir(t, {
    "staging.json": baseConfig(),
  });

  const loaded = loadVoiceAgentConfig({ env: "staging", baseDir: dir });

  assert.equal(loaded.environment, "staging");
  assert.equal(loaded.presetName, "liive-default");
  assert.equal(loaded.sourcePath, path.join(dir, "staging.json"));
  assert.equal(loaded.llm.model, "gpt-4o-mini");
  assert.equal(loaded.locationOverrides, undefined);
});

test("location overrides are deeply merged and marked as applied", (t) => {
  const dir = withConfigDir(t, {
    "prod.json": baseConfig({
      locationOverrides: {
        "brussels-centre": {
          llm: {
            systemPrompt: "Use the Brussels Centre pickup script.",
          },
          tts: {
            voiceId: "voice-brussels",
          },
          tools: [
            {
              name: "submit_order",
              invoke: {
                method: "POST",
                url: "https://brussels-order-service.test/orders",
              },
            },
          ],
        },
      },
    }),
  });

  const loaded = loadVoiceAgentConfig({
    env: "prod",
    baseDir: dir,
    locationCode: "brussels-centre",
  });

  assert.equal(loaded.appliedLocationCode, "brussels-centre");
  assert.equal(loaded.llm.provider, "openai");
  assert.equal(loaded.llm.systemPrompt, "Use the Brussels Centre pickup script.");
  assert.equal(loaded.tts.provider, "elevenlabs");
  assert.equal(loaded.tts.voiceId, "voice-brussels");
  assert.deepEqual(loaded.tools, [
    {
      name: "submit_order",
      invoke: {
        method: "POST",
        url: "https://brussels-order-service.test/orders",
      },
    },
  ]);
  assert.equal(loaded.locationOverrides, undefined);
});

test("returned configs are isolated from subsequent loads", (t) => {
  const dir = withConfigDir(t, {
    "dev.json": baseConfig(),
  });

  const first = loadVoiceAgentConfig({ env: "dev", baseDir: dir });
  first.llm.model = "mutated";
  first.tools[0].invoke.url = "https://mutated.test";

  const second = loadVoiceAgentConfig({ env: "dev", baseDir: dir });
  assert.equal(second.llm.model, "gpt-4o-mini");
  assert.equal(second.tools[0].invoke.url, "https://order-service.test/orders");
});

test("invalid configs fail before reaching runtime", (t) => {
  const dir = withConfigDir(t, {
    "dev.json": {
      presetName: "broken",
      llm: { provider: "openai", model: "gpt-4o-mini" },
      stt: { provider: "deepgram", model: "nova-3" },
      tts: { provider: "elevenlabs", voiceId: "voice-default" },
      tools: [{ name: "submit_order" }],
    },
  });

  assert.throws(
    () => loadVoiceAgentConfig({ env: "dev", baseDir: dir }),
    /Tool at index 0.*missing name or invoke block/
  );
});
