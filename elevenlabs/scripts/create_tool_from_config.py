#!/usr/bin/env python3
"""
Create a new ElevenLabs workspace tool (webhook/client/system) from a local tool config JSON file.

This uses the official ElevenLabs Python SDK (no CLI).

Example:
  ELEVENLABS_API_KEY=... python3 elevenlabs/scripts/create_tool_from_config.py \
    --config elevenlabs/tool_configs/menu_search.json
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


def _load_json(path: str) -> Dict[str, Any]:
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    if not isinstance(data, dict):
        raise RuntimeError(f"Unexpected JSON root type: {type(data).__name__}")
    return data


def main() -> None:
    ap = argparse.ArgumentParser()
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

    api_key = (os.getenv("ELEVENLABS_API_KEY") or os.getenv("XI_API_KEY") or "").strip()
    if not api_key:
        raise SystemExit("ELEVENLABS_API_KEY (or XI_API_KEY) is not set.")
    client = ElevenLabs(api_key=api_key)

    if tool_type == "webhook":
        tool_cfg = WebhookCfg(**cfg)
    elif tool_type == "client":
        tool_cfg = ClientCfg(**cfg)
    else:
        tool_cfg = SystemCfg(**cfg)

    req = ToolRequestModel(tool_config=tool_cfg)
    created = client.conversational_ai.tools.create(request=req)
    out = {
        "tool_id": getattr(created, "id", None),
        "name": getattr(getattr(created, "tool_config", None), "name", None),
        "type": getattr(getattr(created, "tool_config", None), "type", None),
    }
    print(json.dumps(out, indent=2))


if __name__ == "__main__":
    main()

