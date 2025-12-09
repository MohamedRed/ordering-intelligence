# Voice Agent Presets & Location Overrides

These presets capture the baseline configuration for our French-speaking voice agent and define how the persona adapts to different restaurant locations. Because LiveKit Cloud does not yet expose a public preset API or UI, we store the JSON definitions under `infra/voice-agents/` and load them at runtime via the `@ordering-intelligence/voice-agent-config` helper.

## Baseline (all environments)

| Component | Choice | Rationale |
| --- | --- | --- |
| LLM | `openai/gpt-4o-mini` (temperature 0.25–0.30) | Fast, cost-efficient, reliable for structured order dialogs. |
| STT | `deepgram/nova-2-phonecall` (`fr-FR`) | Tuned for PSTN audio and French speech. |
| TTS | `elevenlabs` male voices (default `antoine`, overrides for other regions) | Natural-sounding voices with French accents; low latency streaming. |
| VAD | LiveKit VAD (`mode=aggressive`, `silenceTimeoutMs` 650–700) | Keeps turns snappy on noisy phone lines. |
| Tools | `order_service.lookup_menu`, `order_service.submit_order`, `handoff.request_human` | Same tool set across environments; endpoints swapped via env vars. |
| Safety | Confirmation before submission, low-confidence escalation after 2 turns | Ensures accuracy and easy human fallback. |

## JSON definitions

| Environment | File | Notes |
| --- | --- | --- |
| Dev | `infra/voice-agents/dev.json` | Uses test endpoints and relaxed messaging for internal QA. |
| Staging | `infra/voice-agents/staging.json` | Mirrors production behaviour but points at staging services. |
| Prod | `infra/voice-agents/prod.json` | Production-ready configuration with stricter VAD and confirmation copy. |

Each file contains:
- `presetName` / `description`
- LLM/STT/TTS configuration
- VAD settings
- Tool list (with environment-specific URLs/headers)
- Safety policies
- `locationOverrides` block (see below)

### Runtime loader (`@ordering-intelligence/voice-agent-config`)

Use the shared helper to load presets and apply overrides dynamically inside any worker or service:

```ts
import { loadVoiceAgentConfig } from '@ordering-intelligence/voice-agent-config';

const storeVoiceProfile = { location_code: 'fr-paris' };

const config = loadVoiceAgentConfig({
  env: process.env.APP_ENV === 'production' ? 'prod' : 'staging',
  locationCode: storeVoiceProfile.location_code,
});

// config now contains llm/stt/tts/tool settings with the Paris override applied.
```

The loader looks for JSON files in `infra/voice-agents/` by default and exposes the applied location plus helper types for strong typing. Services that need custom overrides (for example, temporary tool URLs) can pass them via the `overrides` option without mutating the on-disk JSON.

## Location-aware overrides

The `locationOverrides` section allows the admin app to specify a `location_code` (e.g., `fr-paris`, `fr-marseille`, `ca-quebec`). When a store admin picks a location in the Business/Admin app, we persist that code on the store document (`stores.voice_profile.location_code`). The voice agent loader then:

1. Loads the base preset for the environment.
2. Applies the override block that matches `location_code`, updating any of the following fields:
   - `tts.voiceId`, `tts.language`, `tts.style`
   - `stt.language`
   - `llm.systemPrompt` (for region-specific phrasing)
   - Tool headers (e.g., inject `X-Location-Code`)

If no override exists for the selected location, the agent falls back to the baseline voice (Antoine).

### Example overrides

| Location Code | Voice | Changes |
| --- | --- | --- |
| `fr-paris` | ElevenLabs `antoine` (Parisian style) | Adjusted prompt to reference Île-de-France phrasing. |
| `fr-marseille` | ElevenLabs `remy` (southern tone) | Warmer tone and prompt referencing southern France. |
| `fr-lyon` | ElevenLabs `louis` | Neutral accent specific to Lyon. |
| `ca-quebec` | ElevenLabs `marc` (`fr-CA`) | STT/TTS switch to Canadian French, prompt mentions CAD currency. |

## Admin App Integration

1. **Store settings:** add `voice_profile.location_code` dropdown in the Admin app, defaulting to `fr-paris`. The dropdown options should mirror the keys in `locationOverrides`.
2. **Preset selection:** when deploying a store, the provisioning job supplies both the preset ID (`LIVEKIT_VOICE_AGENT_ID_<ENV>`) and the store’s `location_code` to the Voice Agent Worker.
3. **Runtime application:** the worker loads the JSON (or LiveKit preset metadata) and applies the override block before issuing the `AgentSession.start` call.
4. **Hot swapping:** operators can change the location code in the Admin app; the next call uses the updated override without redeploying the preset.

### Firestore schema

- Persist `voice_profile` on every store document, e.g.

  ```json
  {
    "voice_profile": {
      "location_code": "fr-paris",
      "locale": "fr-FR",
      "preferred_voice": "antoine"
    }
  }
  ```

- The Admin app should read the available location codes from the JSON configs (or the helper library) to avoid drift across environments.
- Workers should treat `voice_profile.location_code` as the single source of truth when calling `loadVoiceAgentConfig()`.

## Creating presets in LiveKit Cloud

1. Go to **Agents → Presets** and create a new preset for each environment using the values from the matching JSON file.
2. In the metadata field, store:
   ```json
   {
     "configPath": "infra/voice-agents/dev.json",
     "locationOverrides": true
   }
   ```
3. Copy the generated preset ID into `infra/secrets/.env` under `LIVEKIT_VOICE_AGENT_ID_<ENV>` and update the table in `docs/livekit-sip-migration.md`.
4. Reference the preset in any dispatch rule / agent configuration (e.g., LiveKit Agent Worker) using that ID.

With this structure the Admin app only needs to provide the location; everything else (voices, prompts, languages) flows automatically from the preset metadata.
