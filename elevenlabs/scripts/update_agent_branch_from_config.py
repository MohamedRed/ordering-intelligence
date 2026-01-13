#!/usr/bin/env python3
"""
Update an ElevenLabs agent *branch* configuration from a local agent config JSON file.

Safety: requires --branch-id so we don't accidentally patch Main.

Example:
  ELEVENLABS_API_KEY=... python3 elevenlabs/scripts/update_agent_branch_from_config.py \
    --agent-id agent_7201kbfs3pbpe1tsv4dmakk1207q \
    --branch-id agtbrch_xxxx \
    --config elevenlabs/agent_configs/Order-taker.personalization.json
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


def _request_json(
    *,
    base_url: str,
    api_key: str,
    method: str,
    path: str,
    body: Any | None = None,
) -> Any:
    url = f"{base_url}{path}"
    data = None if body is None else json.dumps(body).encode("utf-8")
    req = request.Request(url, data=data, method=method.upper())
    req.add_header("xi-api-key", api_key)
    req.add_header("Content-Type", "application/json")

    try:
        with request.urlopen(req, timeout=30) as resp:
            raw = resp.read().decode("utf-8")
            if not raw.strip():
                return {}
            return json.loads(raw)
    except error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"ElevenLabs {method} {path} failed status={exc.code} body={detail[:600]}") from exc
    except error.URLError as exc:
        raise RuntimeError(f"ElevenLabs {method} {path} failed: {exc}") from exc


def _load_agent_config(path: str) -> Dict[str, Any]:
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    if not isinstance(data, dict):
        raise RuntimeError(f"Unexpected config root type in {path}: {type(data).__name__}")
    return data


def _deep_merge(base: Any, override: Any) -> Any:
    if isinstance(base, dict) and isinstance(override, dict):
        out: Dict[str, Any] = dict(base)
        for k, v in override.items():
            out[k] = _deep_merge(base.get(k), v)
        return out
    # For lists and primitives: override replaces base.
    return override


def _remove_tools_if_tool_ids_present(body: Dict[str, Any]) -> None:
    try:
        prompt_cfg = body["conversation_config"]["agent"]["prompt"]
        tool_ids = prompt_cfg.get("tool_ids")
        if isinstance(tool_ids, list) and tool_ids:
            prompt_cfg.pop("tools", None)
    except Exception:  # noqa: BLE001
        return


def _build_patch_body(*, cfg: Dict[str, Any], branch_id: str, remote_agent: Optional[Dict[str, Any]]) -> Dict[str, Any]:
    body: Dict[str, Any] = {"branch_id": branch_id}
    # Only include fields that exist in local config; when we do, deep-merge with the current
    # remote branch tip to avoid wiping fields that weren't exported locally (common).
    for k in ("conversation_config", "platform_settings", "workflow", "name", "tags"):
        if k in cfg:
            if isinstance(remote_agent, dict) and isinstance(remote_agent.get(k), dict) and isinstance(cfg.get(k), dict):
                body[k] = _deep_merge(remote_agent.get(k), cfg.get(k))
            else:
                body[k] = cfg[k]
    # Some exports use camelCase, normalize.
    if "conversationConfig" in cfg and "conversation_config" not in body:
        body["conversation_config"] = cfg["conversationConfig"]
    if "platformSettings" in cfg and "platform_settings" not in body:
        body["platform_settings"] = cfg["platformSettings"]
    _remove_tools_if_tool_ids_present(body)
    return body


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--agent-id", required=True)
    ap.add_argument("--branch-id", required=True, help="agtbrch_... (required for safety)")
    ap.add_argument("--config", required=True, help="Local agent config JSON to apply")
    ap.add_argument("--api-base-url", default=None)
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    api_key = _api_key()
    if not api_key:
        raise SystemExit("ELEVENLABS_API_KEY (or XI_API_KEY) is not set.")
    base_url = _api_base_url(args.api_base_url)

    cfg = _load_agent_config(args.config)

    remote_agent: Optional[Dict[str, Any]] = None
    try:
        fetched = _request_json(
            base_url=base_url,
            api_key=api_key,
            method="GET",
            path=f"/v1/convai/agents/{args.agent_id}?branch_id={args.branch_id}",
        )
        if isinstance(fetched, dict):
            remote_agent = fetched
    except Exception as exc:  # noqa: BLE001
        sys.stderr.write(f"warn: could not fetch remote branch tip for merge; patching with local config only: {exc}\n")

    body = _build_patch_body(cfg=cfg, branch_id=args.branch_id.strip(), remote_agent=remote_agent)

    if args.dry_run:
        print(json.dumps(body, indent=2))
        return

    # Try a few likely endpoint shapes. If none work, print guidance.
    paths = [
        f"/v1/convai/agents/{args.agent_id}?branch_id={args.branch_id}",
        f"/v1/convai/agents/{args.agent_id}?branchId={args.branch_id}",
        # Fallback: some APIs accept branch_id in the body without query params.
        f"/v1/convai/agents/{args.agent_id}",
    ]
    last_err: Optional[Exception] = None
    for path in paths:
        try:
            out = _request_json(base_url=base_url, api_key=api_key, method="PATCH", path=path, body=body)
            print(f"Patched branch via {path}")
            print(json.dumps({"agent_id": args.agent_id, "branch_id": args.branch_id, "result_keys": list(out.keys()) if isinstance(out, dict) else None}, indent=2))
            return
        except Exception as exc:  # noqa: BLE001
            last_err = exc
            continue

    raise SystemExit(
        "Failed to patch agent branch via all known endpoint variants.\n"
        f"Last error: {last_err}\n"
        "If you can share the 404/422 response body, I can adjust the endpoint/shape."
    )


if __name__ == "__main__":
    main()
