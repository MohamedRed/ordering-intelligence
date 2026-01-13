#!/usr/bin/env python3
"""
Update an ElevenLabs workspace tool (webhook/client/system) from a local tool config JSON file.

This uses the official ElevenLabs Python SDK for tool updates (no CLI).

WARNING: Tools are workspace-level (not per-agent-branch), so updating a tool affects any agent
that references the same tool_id.

Example:
  ELEVENLABS_API_KEY=... python3 elevenlabs/scripts/update_tool_from_config.py \
    --tool-id tool_6401kc5jcrtnfc08v8tv3jgms7t7 \
    --config elevenlabs/tool_configs/order_create.json
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from typing import Any, Dict


def _import_elevenlabs_sdk():
    # Avoid importing the repo-local ./elevenlabs directory as a python package.
    if sys.path and sys.path[0] == "":
        sys.path.pop(0)
    from elevenlabs.client import ElevenLabs  # type: ignore
    from elevenlabs.types.tool_request_model import ToolRequestModel  # type: ignore
    from elevenlabs.types.tool_request_model_tool_config import (  # type: ignore
        ToolRequestModelToolConfig_Webhook,
        ToolRequestModelToolConfig_Client,
        ToolRequestModelToolConfig_System,
    )

    return ElevenLabs, ToolRequestModel, ToolRequestModelToolConfig_Webhook, ToolRequestModelToolConfig_Client, ToolRequestModelToolConfig_System


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


def _load_json(path: str) -> Dict[str, Any]:
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    if not isinstance(data, dict):
        raise RuntimeError(f"Unexpected JSON root type: {type(data).__name__}")
    return data


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--tool-id", required=True)
    ap.add_argument("--config", required=True, help="Local tool config JSON file")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    ElevenLabs, ToolRequestModel, WebhookCfg, ClientCfg, SystemCfg = _import_elevenlabs_sdk()

    cfg = _load_json(args.config)
    tool_type = cfg.get("type")
    if tool_type not in ("webhook", "client", "system"):
        raise SystemExit(f"Unsupported tool type in config: {tool_type!r}")

    if args.dry_run:
        print(json.dumps(cfg, indent=2))
        return

    api_key = _api_key()
    if not api_key:
        raise SystemExit("ELEVENLABS_API_KEY (or XI_API_KEY) is not set, and GCP Secret Manager fallback failed.")
    client = ElevenLabs(api_key=api_key)

    if tool_type == "webhook":
        tool_cfg = WebhookCfg(**cfg)
    elif tool_type == "client":
        tool_cfg = ClientCfg(**cfg)
    else:
        tool_cfg = SystemCfg(**cfg)

    req = ToolRequestModel(tool_config=tool_cfg)
    updated = client.conversational_ai.tools.update(args.tool_id, request=req)
    out = {
        "tool_id": getattr(updated, "id", args.tool_id),
        "name": getattr(getattr(updated, "tool_config", None), "name", None),
        "type": getattr(getattr(updated, "tool_config", None), "type", None),
    }
    print(json.dumps(out, indent=2))


if __name__ == "__main__":
    main()
