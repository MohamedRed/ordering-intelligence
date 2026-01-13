#!/usr/bin/env python3
"""
Add a workspace tool_id to an ElevenLabs agent *branch* (versioning), and optionally
inject a short prompt instruction for the new tool.

This uses:
- GCP Secret Manager to fetch the ElevenLabs API key (default secret: elevenlabs-api-key)
- Direct ElevenLabs HTTP API calls for branch patching

Example:
  python3 elevenlabs/scripts/add_tool_to_agent_branch.py \\
    --agent-id agent_... \\
    --branch-id agtbrch_... \\
    --tool-id tool_... \\
    --tool-name agent_tools_wait_time_estimate \\
    --add-eta-refresh-guidance
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from typing import Any, Dict, Optional
from urllib import error, request

import google.auth  # type: ignore
from google.cloud import secretmanager  # type: ignore


DEFAULT_API_BASE_URL = "https://api.elevenlabs.io"


def _api_base_url(cli_override: Optional[str]) -> str:
    base = (cli_override or os.getenv("ELEVENLABS_API_BASE_URL") or DEFAULT_API_BASE_URL).strip()
    return re.sub(r"/+$", "", base)


def _get_gcp_project_id(explicit: str) -> str:
    pid = (explicit or os.getenv("GOOGLE_CLOUD_PROJECT") or os.getenv("GCP_PROJECT") or "").strip()
    if pid:
        return pid
    try:
        _creds, project_id = google.auth.default()
        if project_id:
            return str(project_id).strip()
    except Exception:  # noqa: BLE001
        pass
    try:
        res = subprocess.run(
            ["gcloud", "config", "get-value", "project"],
            check=False,
            capture_output=True,
            text=True,
        )
        candidate = (res.stdout or "").strip()
        if candidate:
            return candidate
    except Exception:  # noqa: BLE001
        pass
    raise SystemExit("Missing --gcp-project-id (and could not infer GCP project).")


def _read_secret(*, project_id: str, secret_id: str, version: str = "latest") -> str:
    client = secretmanager.SecretManagerServiceClient()
    name = f"projects/{project_id}/secrets/{secret_id}/versions/{version}"
    resp = client.access_secret_version(request={"name": name})
    return resp.payload.data.decode("utf-8").strip()


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


def _get_agent_branch(*, base_url: str, api_key: str, agent_id: str, branch_id: str) -> Dict[str, Any]:
    out = _request_json(
        base_url=base_url,
        api_key=api_key,
        method="GET",
        path=f"/v1/convai/agents/{agent_id}?branch_id={branch_id}",
    )
    if not isinstance(out, dict):
        raise RuntimeError("Unexpected agent response type")
    return out


def _ensure_tool_id(conversation_config: Dict[str, Any], tool_id: str) -> bool:
    agent = conversation_config.get("agent")
    if not isinstance(agent, dict):
        return False
    prompt = agent.get("prompt")
    if not isinstance(prompt, dict):
        return False
    tool_ids = prompt.get("tool_ids")
    if not isinstance(tool_ids, list):
        tool_ids = []
    if tool_id not in tool_ids:
        tool_ids.append(tool_id)
    prompt["tool_ids"] = tool_ids
    # Avoid patch rejection when both tool_ids and tools are present.
    if tool_ids:
        prompt.pop("tools", None)
    return True


def _ensure_eta_guidance(conversation_config: Dict[str, Any], tool_name: str) -> bool:
    agent = conversation_config.get("agent")
    if not isinstance(agent, dict):
        return False
    prompt_cfg = agent.get("prompt")
    if not isinstance(prompt_cfg, dict):
        return False
    text = prompt_cfg.get("prompt")
    if not isinstance(text, str) or not text.strip():
        return False
    if tool_name in text:
        return False
    marker = "When calling backend tools, use the tenant context values above."
    insert = (
        "\\n\\n# ETA refresh\\n"
        f"- If the customer asks for an updated wait time, call `{tool_name}` for the current `storeId` and answer using its `etaMinutes`.\\n"
    )
    if marker in text:
        text = text.replace(marker, marker + insert, 1)
    else:
        text = text + insert
    prompt_cfg["prompt"] = text
    return True


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--agent-id", required=True)
    ap.add_argument("--branch-id", required=True)
    ap.add_argument("--tool-id", required=True)
    ap.add_argument("--tool-name", default="agent_tools_wait_time_estimate")
    ap.add_argument("--api-base-url", default=None)
    ap.add_argument("--gcp-project-id", default="")
    ap.add_argument("--secret-id", default="elevenlabs-api-key")
    ap.add_argument("--add-eta-refresh-guidance", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    base_url = _api_base_url(args.api_base_url)
    project_id = _get_gcp_project_id(args.gcp_project_id)
    api_key = _read_secret(project_id=project_id, secret_id=args.secret_id, version="latest")
    if not api_key:
        raise SystemExit("ElevenLabs API key secret is empty")

    agent = _get_agent_branch(base_url=base_url, api_key=api_key, agent_id=args.agent_id, branch_id=args.branch_id)
    cc = agent.get("conversation_config")
    if not isinstance(cc, dict):
        raise SystemExit("Agent response missing conversation_config")

    changed = False
    changed = _ensure_tool_id(cc, args.tool_id.strip()) or changed
    if args.add_eta_refresh_guidance:
        changed = _ensure_eta_guidance(cc, args.tool_name.strip()) or changed

    if args.dry_run:
        print(json.dumps({"changed": changed, "branch_id": args.branch_id, "tool_id": args.tool_id}, indent=2))
        return

    if not changed:
        print(json.dumps({"status": "no_change", "branch_id": args.branch_id, "tool_id": args.tool_id}, indent=2))
        return

    body = {"branch_id": args.branch_id, "conversation_config": cc}
    out = _request_json(
        base_url=base_url,
        api_key=api_key,
        method="PATCH",
        path=f"/v1/convai/agents/{args.agent_id}?branch_id={args.branch_id}",
        body=body,
    )
    if not isinstance(out, dict):
        print(json.dumps({"status": "patched", "branch_id": args.branch_id, "tool_id": args.tool_id}, indent=2))
        return
    print(json.dumps({"status": "patched", "branch_id": args.branch_id, "tool_id": args.tool_id, "version_id": out.get("version_id")}, indent=2))


if __name__ == "__main__":
    main()
