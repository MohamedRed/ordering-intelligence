#!/usr/bin/env python3
"""
Inject personalization + order identity instructions into an ElevenLabs agent config prompt.

This edits local JSON config files (agent_configs/*.json). Use this to prepare the prompt
text you’ll apply on your ElevenLabs versioning branch.

Example:
  python3 elevenlabs/scripts/apply_personalization_instructions.py \
    --config elevenlabs/agent_configs/Order-taker.json \
    --out elevenlabs/agent_configs/Order-taker.personalization.json
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from typing import Any, Dict


START = "<!-- PERSONALIZATION_START -->"
END = "<!-- PERSONALIZATION_END -->"


BLOCK = """<!-- PERSONALIZATION_START -->
# Personalization (dynamic variables)

At the start of the call, use the dynamic variables provided by conversation-init:

- If `{{isReturningCustomer}}` is `true` and `{{customerName}}` is non-empty:
  - greet the caller by name (example in French: “Ravi de vous revoir, {{customerName}}.”).
- If `{{topReorders}}` is a non-empty JSON list:
  - suggest the first reorder from `{{topReorders}}` (use its `title` and/or `items`) before continuing with the normal order-taking flow.

## Creating an order (important)

When calling the create-order tool, always include:

- `tenantId` = `{{tenantId}}`
- `storeId` = `{{storeId}}`
- `callerId` = `{{callerId}}`
- `callSid` = `{{callSid}}`
- `customerName` = `{{customerName}}` (if empty, ask for the customer’s name first)
- `channel` = `"voice"`

<!-- PERSONALIZATION_END -->"""


def load_json(path: str) -> Dict[str, Any]:
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    if not isinstance(data, dict):
        raise RuntimeError(f"Unexpected JSON root type in {path}: {type(data).__name__}")
    return data


def dump_json(path: str, data: Dict[str, Any]) -> None:
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=True, indent=4)
        f.write("\n")


def inject(prompt: str) -> str:
    if START in prompt and END in prompt:
        pattern = re.compile(re.escape(START) + r".*?" + re.escape(END), re.DOTALL)
        return pattern.sub(BLOCK, prompt)

    tenant_marker = "# Tenant context"
    idx = prompt.find(tenant_marker)
    if idx == -1:
        return BLOCK + "\n\n" + prompt.lstrip()

    after = prompt[idx:]
    m = re.search(r"\n# ", after[1:])  # skip the very first '#'
    if not m:
        return prompt.rstrip() + "\n\n" + BLOCK + "\n"

    insert_at = idx + 1 + m.start()
    return prompt[:insert_at].rstrip() + "\n\n" + BLOCK + "\n\n" + prompt[insert_at:].lstrip()


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", required=True, help="Input agent config JSON")
    ap.add_argument("--out", required=True, help="Output path for patched config JSON")
    args = ap.parse_args()

    cfg = load_json(args.config)
    try:
        prompt = cfg["conversation_config"]["agent"]["prompt"]["prompt"]
    except KeyError as exc:
        raise SystemExit(f"Prompt field not found in config: {exc}") from exc
    if not isinstance(prompt, str):
        raise SystemExit("Prompt field is not a string")

    cfg["conversation_config"]["agent"]["prompt"]["prompt"] = inject(prompt)

    dump_json(args.out, cfg)
    print(f"Wrote patched config: {args.out}")


if __name__ == "__main__":
    main()
