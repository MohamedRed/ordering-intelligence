#!/usr/bin/env python3
"""
Sync ElevenLabs workspace tools from elevenlabs/tools.json using the official ElevenLabs Python SDK.

- No ElevenLabs CLI usage.
- Updates existing tools by tool_id from the manifest.

Examples:
  ELEVENLABS_API_KEY=... python3 elevenlabs/scripts/sync_tools_from_manifest.py
  ELEVENLABS_API_KEY=... python3 elevenlabs/scripts/sync_tools_from_manifest.py --only order_
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple


REPO_ROOT = Path(__file__).resolve().parents[2]
MANIFEST_PATH = REPO_ROOT / "elevenlabs" / "tools.json"


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

    return (
        ElevenLabs,
        ToolRequestModel,
        ToolRequestModelToolConfig_Webhook,
        ToolRequestModelToolConfig_Client,
        ToolRequestModelToolConfig_System,
    )


def _load_json(path: Path) -> Dict[str, Any]:
    with path.open("r", encoding="utf-8") as f:
        data = json.load(f)
    if not isinstance(data, dict):
        raise RuntimeError(f"Unexpected JSON root type for {path}: {type(data).__name__}")
    return data


def _tool_req_from_cfg(cfg: Dict[str, Any]):
    ElevenLabs, ToolRequestModel, WebhookCfg, ClientCfg, SystemCfg = _import_elevenlabs_sdk()
    tool_type = cfg.get("type")
    if tool_type == "webhook":
        tool_cfg = WebhookCfg(**cfg)
    elif tool_type == "client":
        tool_cfg = ClientCfg(**cfg)
    elif tool_type == "system":
        tool_cfg = SystemCfg(**cfg)
    else:
        raise RuntimeError(f"Unsupported tool type in config: {tool_type!r}")
    return ToolRequestModel(tool_config=tool_cfg)


def _api_key() -> str:
    return (os.getenv("ELEVENLABS_API_KEY") or os.getenv("XI_API_KEY") or "").strip()


def _iter_manifest_entries(manifest: Dict[str, Any]) -> List[Tuple[str, str, str]]:
    tools = manifest.get("tools")
    if not isinstance(tools, list):
        raise RuntimeError("Manifest missing tools[]")
    out: List[Tuple[str, str, str]] = []
    for t in tools:
        if not isinstance(t, dict):
            continue
        tool_id = str(t.get("id") or "").strip()
        cfg_path = str(t.get("config") or "").strip()
        tool_type = str(t.get("type") or "").strip()
        if not tool_id or not cfg_path:
            continue
        out.append((tool_id, cfg_path, tool_type))
    return out


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--manifest", default=str(MANIFEST_PATH))
    ap.add_argument("--only", default="", help="Only sync tools whose config path contains this substring")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    manifest_path = Path(args.manifest).resolve()
    manifest = _load_json(manifest_path)

    entries = _iter_manifest_entries(manifest)
    if args.only:
        entries = [e for e in entries if args.only in e[1]]
    if not entries:
        print("No tools matched.")
        return

    client = None
    if not args.dry_run:
        api_key = _api_key()
        if not api_key:
            raise SystemExit("ELEVENLABS_API_KEY (or XI_API_KEY) is not set.")
        ElevenLabs, *_ = _import_elevenlabs_sdk()
        client = ElevenLabs(api_key=api_key)

    for tool_id, rel_cfg_path, _tool_type in entries:
        cfg_file = (manifest_path.parent / rel_cfg_path).resolve()
        cfg = _load_json(cfg_file)

        req = _tool_req_from_cfg(cfg)
        name = str(cfg.get("name") or "").strip()
        if args.dry_run:
            print(json.dumps({"tool_id": tool_id, "config": rel_cfg_path, "name": name}, indent=2))
            continue

        updated = client.conversational_ai.tools.update(tool_id, request=req)  # type: ignore[union-attr]
        out = {
            "tool_id": getattr(updated, "id", tool_id),
            "name": getattr(getattr(updated, "tool_config", None), "name", None),
            "type": getattr(getattr(updated, "tool_config", None), "type", None),
            "config": rel_cfg_path,
        }
        print(json.dumps(out, indent=2))


if __name__ == "__main__":
    main()
