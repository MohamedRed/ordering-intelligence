#!/usr/bin/env python3
"""
Patch an ElevenLabs agent *branch* to include personalization instructions, without changing LLM settings.

This fetches the current agent config at the branch tip, injects a prompt block, then PATCHes the same
branch back using the existing prompt config (so we don't trip validation on model-specific fields like
reasoning_effort/thinking_budget).

Example:
  ELEVENLABS_API_KEY=... python3 elevenlabs/scripts/patch_branch_personalization.py \\
    --agent-id agent_7201kbfs3pbpe1tsv4dmakk1207q \\
    --branch-id agtbrch_xxxx
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from typing import Any, Dict, Optional
from urllib import error, request


DEFAULT_API_BASE_URL = "https://api.elevenlabs.io"

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


def _api_key() -> str:
    return (os.getenv("ELEVENLABS_API_KEY") or os.getenv("XI_API_KEY") or "").strip()


def _api_base_url(cli_override: Optional[str]) -> str:
    base = (cli_override or os.getenv("ELEVENLABS_API_BASE_URL") or DEFAULT_API_BASE_URL).strip()
    return re.sub(r"/+$", "", base)


def _request_json(*, base_url: str, api_key: str, method: str, path: str, body: Any | None = None) -> Any:
    url = f"{base_url}{path}"
    data = None if body is None else json.dumps(body).encode("utf-8")
    req = request.Request(url, data=data, method=method.upper())
    req.add_header("xi-api-key", api_key)
    req.add_header("Content-Type", "application/json")
    try:
        with request.urlopen(req, timeout=30) as resp:
            raw = resp.read().decode("utf-8")
            return json.loads(raw) if raw.strip() else {}
    except error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"ElevenLabs {method} {path} failed status={exc.code} body={detail[:600]}") from exc
    except error.URLError as exc:
        raise RuntimeError(f"ElevenLabs {method} {path} failed: {exc}") from exc


def _inject(prompt: str) -> str:
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


def _remove_block(prompt: str) -> str:
    if START not in prompt or END not in prompt:
        return prompt
    pattern = re.compile(re.escape(START) + r".*?" + re.escape(END), re.DOTALL)
    out = pattern.sub("", prompt)
    # Clean up excessive blank lines from removal.
    out = re.sub(r"\n{3,}", "\n\n", out).strip() + "\n"
    return out


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--agent-id", required=True)
    ap.add_argument("--branch-id", required=True)
    ap.add_argument("--api-base-url", default=None)
    ap.add_argument("--backup", default="", help="Optional path to write fetched agent JSON before patching.")
    ap.add_argument("--remove", action="store_true", help="Remove the personalization block instead of adding/updating it.")
    args = ap.parse_args()

    api_key = _api_key()
    if not api_key:
        raise SystemExit("ELEVENLABS_API_KEY (or XI_API_KEY) is not set.")
    base_url = _api_base_url(args.api_base_url)

    # Fetch agent config at branch tip.
    agent = _request_json(
        base_url=base_url,
        api_key=api_key,
        method="GET",
        path=f"/v1/convai/agents/{args.agent_id}?branch_id={args.branch_id}",
    )
    if not isinstance(agent, dict):
        raise SystemExit(f"Unexpected agent response type: {type(agent).__name__}")

    if args.backup:
        os.makedirs(os.path.dirname(args.backup) or ".", exist_ok=True)
        with open(args.backup, "w", encoding="utf-8") as f:
            json.dump(agent, f, ensure_ascii=True, indent=2)
            f.write("\n")

    cc = agent.get("conversation_config")
    if not isinstance(cc, dict):
        raise SystemExit("Agent missing conversation_config")
    agent_cfg = cc.get("agent")
    if not isinstance(agent_cfg, dict):
        raise SystemExit("Agent missing conversation_config.agent")
    prompt_cfg = agent_cfg.get("prompt")
    if not isinstance(prompt_cfg, dict):
        raise SystemExit("Agent missing conversation_config.agent.prompt")
    prompt_text = prompt_cfg.get("prompt")
    if not isinstance(prompt_text, str):
        raise SystemExit("Agent prompt.prompt is not a string")

    prompt_cfg["prompt"] = _remove_block(prompt_text) if args.remove else _inject(prompt_text)

    # Some agent exports include both tool_ids and tools; the API rejects PATCH when both are present.
    if isinstance(prompt_cfg.get("tool_ids"), list) and prompt_cfg.get("tool_ids"):
        prompt_cfg.pop("tools", None)

    # Patch only the conversation_config back to the branch; keep all model-specific keys intact.
    body = {"conversation_config": cc}
    _request_json(
        base_url=base_url,
        api_key=api_key,
        method="PATCH",
        path=f"/v1/convai/agents/{args.agent_id}?branch_id={args.branch_id}",
        body=body,
    )

    print("Updated branch prompt")
    print(f"- agent_id: {args.agent_id}")
    print(f"- branch_id: {args.branch_id}")
    print(f"- mode: {'remove' if args.remove else 'apply'}")


if __name__ == "__main__":
    main()
