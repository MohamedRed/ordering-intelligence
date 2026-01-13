#!/usr/bin/env python3
"""
Copy the current Main agent config onto an existing ElevenLabs agent *branch*.

Use this when a branch drifted (e.g., patched from an out-of-date local export) and you want to
re-align it with Main before applying a small patch.

Example:
  ELEVENLABS_API_KEY=... python3 elevenlabs/scripts/sync_branch_from_main.py \\
    --agent-id agent_... \\
    --branch-id agtbrch_...
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
        raise RuntimeError(f"ElevenLabs {method} {path} failed status={exc.code} body={detail[:800]}") from exc
    except error.URLError as exc:
        raise RuntimeError(f"ElevenLabs {method} {path} failed: {exc}") from exc


def _build_patch_from_main(main_agent: Dict[str, Any], branch_id: str) -> Dict[str, Any]:
    body: Dict[str, Any] = {"branch_id": branch_id}
    for k in ("conversation_config", "platform_settings", "workflow", "name", "tags"):
        if k in main_agent:
            body[k] = main_agent[k]
    # ElevenLabs rejects PATCH when both tool_ids and tools are present in the prompt config.
    try:
        prompt_cfg = body["conversation_config"]["agent"]["prompt"]
        tool_ids = prompt_cfg.get("tool_ids")
        if isinstance(tool_ids, list) and tool_ids:
            prompt_cfg.pop("tools", None)
    except Exception:  # noqa: BLE001
        pass
    return body


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--agent-id", required=True)
    ap.add_argument("--branch-id", required=True)
    ap.add_argument("--api-base-url", default=None)
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    api_key = _api_key()
    if not api_key:
        raise SystemExit("ELEVENLABS_API_KEY (or XI_API_KEY) is not set.")
    base_url = _api_base_url(args.api_base_url)

    main_agent = _request_json(
        base_url=base_url,
        api_key=api_key,
        method="GET",
        path=f"/v1/convai/agents/{args.agent_id}",
    )
    if not isinstance(main_agent, dict):
        raise SystemExit(f"Unexpected main agent response type: {type(main_agent).__name__}")

    body = _build_patch_from_main(main_agent, args.branch_id.strip())
    if args.dry_run:
        print(json.dumps({"agent_id": args.agent_id, "branch_id": args.branch_id, "patch_keys": sorted(body.keys())}, indent=2))
        return

    out = _request_json(
        base_url=base_url,
        api_key=api_key,
        method="PATCH",
        path=f"/v1/convai/agents/{args.agent_id}?branch_id={args.branch_id}",
        body=body,
    )
    result_keys = list(out.keys()) if isinstance(out, dict) else None
    print("Synced branch from Main")
    print(json.dumps({"agent_id": args.agent_id, "branch_id": args.branch_id, "result_keys": result_keys}, indent=2))


if __name__ == "__main__":
    main()
