#!/usr/bin/env python3
"""
Print the configured dynamic variable placeholders for an ElevenLabs agent (optionally for a specific branch).

This helps debug cases where the web-console Preview shows fewer variables than expected.

Example:
  ELEVENLABS_API_KEY=... python3 elevenlabs/scripts/print_agent_dynamic_vars.py --agent-id agent_...
  ELEVENLABS_API_KEY=... python3 elevenlabs/scripts/print_agent_dynamic_vars.py --agent-id agent_... --branch-id agtbrch_...
"""

from __future__ import annotations

import argparse
import json
import os
import re
from typing import Any, Dict, Optional
from urllib import error, request


DEFAULT_API_BASE_URL = "https://api.elevenlabs.io"


def _api_key() -> str:
    key = (os.getenv("ELEVENLABS_API_KEY") or os.getenv("XI_API_KEY") or "").strip()
    if key:
        return key

    project_id = (os.getenv("GCP_PROJECT") or "ordering-intelligence").strip()
    secret_id = (os.getenv("ELEVENLABS_API_KEY_SECRET_ID") or "elevenlabs-api-key").strip()
    if not project_id or not secret_id:
        return ""
    try:
        from google.cloud import secretmanager  # type: ignore

        client = secretmanager.SecretManagerServiceClient()
        name = f"projects/{project_id}/secrets/{secret_id}/versions/latest"
        resp = client.access_secret_version(request={"name": name})
        return resp.payload.data.decode("utf-8").strip()
    except Exception:  # noqa: BLE001
        return ""


def _api_base_url(cli_override: Optional[str]) -> str:
    base = (cli_override or os.getenv("ELEVENLABS_API_BASE_URL") or DEFAULT_API_BASE_URL).strip()
    return re.sub(r"/+$", "", base)


def _request_json(*, base_url: str, api_key: str, method: str, path: str) -> Any:
    url = f"{base_url}{path}"
    req = request.Request(url, method=method.upper())
    req.add_header("xi-api-key", api_key)
    req.add_header("Content-Type", "application/json")
    try:
        with request.urlopen(req, timeout=30) as resp:
            raw = resp.read().decode("utf-8")
            return json.loads(raw) if raw.strip() else {}
    except error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"ElevenLabs {method} {path} failed status={exc.code} body={detail[:800]}") from exc


def _extract_placeholders(agent: Dict[str, Any]) -> Dict[str, Any]:
    cc = agent.get("conversation_config") or {}
    agent_cfg = (cc.get("agent") or {}) if isinstance(cc, dict) else {}
    dv = agent_cfg.get("dynamic_variables") or {}
    placeholders = dv.get("dynamic_variable_placeholders") or {}
    return placeholders if isinstance(placeholders, dict) else {}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--agent-id", required=True)
    ap.add_argument("--branch-id", default="")
    ap.add_argument("--api-base-url", default=None)
    args = ap.parse_args()

    api_key = _api_key()
    if not api_key:
        raise SystemExit("ELEVENLABS_API_KEY (or XI_API_KEY) is not set.")
    base_url = _api_base_url(args.api_base_url)

    path = f"/v1/convai/agents/{args.agent_id}"
    if args.branch_id.strip():
        path += f"?branch_id={args.branch_id.strip()}"
    agent = _request_json(base_url=base_url, api_key=api_key, method="GET", path=path)
    if not isinstance(agent, dict):
        raise SystemExit(f"Unexpected agent response type: {type(agent).__name__}")

    placeholders = _extract_placeholders(agent)
    print(
        json.dumps(
            {
                "agent_id": args.agent_id,
                "branch_id": args.branch_id.strip() or None,
                "version_id": agent.get("version_id"),
                "dynamic_variable_placeholder_keys": sorted(placeholders.keys()),
                "dynamic_variable_placeholder_count": len(placeholders),
            },
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
