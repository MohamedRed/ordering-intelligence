#!/usr/bin/env python3
"""
Reset (delete + recreate) ElevenLabs ConvAI workspace tools from a local directory of tool config JSON files.

This is a SDK-based replacement for scripts that previously used the ElevenLabs CLI.

WARNING: Tool IDs will change when recreated. Use --output-manifest to write a new manifest mapping.

Example (TecDoc clean set):
  ELEVENLABS_API_KEY=... python3 elevenlabs/scripts/reset_tools_from_local.py \\
    --config-dir elevenlabs/tool_configs_clean \\
    --delete-mode matching \\
    --output-manifest elevenlabs/tools.tecdoc.generated.json
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional


REPO_ROOT = Path(__file__).resolve().parents[2]


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
    return (os.getenv("ELEVENLABS_API_KEY") or os.getenv("XI_API_KEY") or "").strip()


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


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--config-dir", required=True, help="Directory containing tool config JSON files.")
    ap.add_argument(
        "--delete-mode",
        choices=["none", "all", "matching"],
        default="matching",
        help="Delete which existing tools before recreating. 'matching' deletes tools whose name matches a local config name.",
    )
    ap.add_argument("--output-manifest", default="", help="Optional output JSON path for new tool_id -> config mapping.")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    api_key = _api_key()
    if not api_key and not args.dry_run:
        raise SystemExit("ELEVENLABS_API_KEY (or XI_API_KEY) is not set.")

    config_dir = Path(args.config_dir).resolve()
    if not config_dir.exists() or not config_dir.is_dir():
        raise SystemExit(f"config-dir not found or not a directory: {config_dir}")

    cfg_files = sorted([p for p in config_dir.glob("*.json") if p.is_file()])
    if not cfg_files:
        raise SystemExit(f"No *.json configs found in {config_dir}")

    local_cfgs: List[Dict[str, Any]] = []
    local_names: List[str] = []
    for p in cfg_files:
        cfg = _load_json(p)
        name = str(cfg.get("name") or "").strip()
        if not name:
            raise SystemExit(f"Tool config missing name: {p}")
        local_cfgs.append(cfg)
        local_names.append(name)

    if args.dry_run:
        print(json.dumps({"config_dir": str(config_dir), "tools": [{"file": str(p), "name": n} for p, n in zip(cfg_files, local_names)]}, indent=2))
        return

    ElevenLabs, *_ = _import_elevenlabs_sdk()
    client = ElevenLabs(api_key=api_key)

    existing = client.conversational_ai.tools.list().tools

    to_delete: List[str] = []
    if args.delete_mode == "all":
        to_delete = [getattr(t, "id", "") for t in existing if getattr(t, "id", "")]
    elif args.delete_mode == "matching":
        for t in existing:
            tc = getattr(t, "tool_config", None)
            if tc is None:
                continue
            name = getattr(tc, "name", "") or ""
            if name in local_names:
                tool_id = getattr(t, "id", "")
                if tool_id:
                    to_delete.append(tool_id)

    deleted = 0
    for tool_id in to_delete:
        try:
            client.conversational_ai.tools.delete(tool_id)
            deleted += 1
        except Exception as exc:  # noqa: BLE001
            print(f"[convai] delete failed tool_id={tool_id} err={exc}", file=sys.stderr)

    created_entries: List[Dict[str, str]] = []
    for cfg_file, cfg in zip(cfg_files, local_cfgs):
        req = _tool_req_from_cfg(cfg)
        created = client.conversational_ai.tools.create(request=req)
        created_id = getattr(created, "id", "")
        rel_cfg = str(cfg_file.relative_to(REPO_ROOT))
        created_entries.append({"id": created_id, "type": str(cfg.get("type") or ""), "config": rel_cfg})
        print(f"[convai] created tool name={cfg.get('name')} id={created_id}")

    if args.output_manifest:
        out_path = Path(args.output_manifest).resolve()
        out_path.parent.mkdir(parents=True, exist_ok=True)
        with out_path.open("w", encoding="utf-8") as f:
            json.dump({"tools": created_entries}, f, indent=2)
            f.write("\n")
        print(f"[convai] wrote manifest: {out_path}")

    print(f"[convai] done; deleted={deleted} created={len(created_entries)}")


if __name__ == "__main__":
    main()

