#!/usr/bin/env python3
import json
import os
import sys
from typing import Any, Dict

# NOTE: agent-tools menu snapshot returns a voice-optimized payload including `spokenMenuFr`
# and `priceSpeechFr`. See scripts/elevenlabs/VOICE_MENU_GUIDANCE.md.


def _env(name: str) -> str:
    v = os.getenv(name, "").strip()
    if not v:
        raise SystemExit(f"missing env var: {name}")
    return v


def _import_elevenlabs_sdk():
    # Avoid importing the repo-local ./elevenlabs directory as a python package.
    if sys.path and sys.path[0] == "":
        sys.path.pop(0)
    from elevenlabs.client import ElevenLabs  # type: ignore
    from elevenlabs.types.tool_request_model import ToolRequestModel  # type: ignore
    from elevenlabs.types.tool_request_model_tool_config import ToolRequestModelToolConfig_Webhook  # type: ignore

    return ElevenLabs, ToolRequestModel, ToolRequestModelToolConfig_Webhook


def remap_url(old: str, new_base: str) -> str:
    # Map order-service endpoints to agent-tools proxy endpoints.
    if old.endswith("/stores/{storeId}/menu/snapshot"):
        return new_base + "/v1/stores/{storeId}/menu/snapshot"
    if old.endswith("/orders"):
        return new_base + "/v1/orders"
    if old.endswith("/orders/{orderId}"):
        return new_base + "/v1/orders/{orderId}"
    if old.endswith("/orders/{orderId}/status"):
        return new_base + "/v1/orders/{orderId}/status"
    return old


def main():
    api_key = _env("ELEVENLABS_API_KEY")
    new_base = _env("AGENT_TOOLS_LB_BASE").rstrip("/")
    shared_key = _env("AGENT_TOOLS_X_API_KEY")

    ElevenLabs, ToolRequestModel, WebhookCfg = _import_elevenlabs_sdk()
    client = ElevenLabs(api_key=api_key)
    tools = client.conversational_ai.tools.list().tools

    updated = 0
    for t in tools:
        tool_id = getattr(t, "id", "")
        tc = getattr(t, "tool_config", None)
        if tc is None or getattr(tc, "type", None) != "webhook":
            continue
        name = getattr(tc, "name", "") or ""
        if not name.startswith("order_service_"):
            continue
        api_schema = getattr(tc, "api_schema", None)
        if api_schema is None:
            continue
        old_url = getattr(api_schema, "url", "") or ""
        new_url = remap_url(old_url, new_base)
        if new_url == old_url:
            continue

        headers: Dict[str, Any] = dict(getattr(api_schema, "request_headers", None) or {})
        headers["X-API-Key"] = shared_key

        tc_dict: Dict[str, Any] = tc.model_dump(exclude_none=True)  # type: ignore[attr-defined]
        tc_dict["api_schema"] = dict(tc_dict.get("api_schema") or {})
        tc_dict["api_schema"]["url"] = new_url
        tc_dict["api_schema"]["request_headers"] = headers

        req = ToolRequestModel(tool_config=WebhookCfg(**tc_dict))
        try:
            client.conversational_ai.tools.update(tool_id, request=req)
        except Exception as exc:  # noqa: BLE001
            print(f"[convai] failed updating tool id={tool_id} name={name} err={exc}", file=sys.stderr)
            continue

        updated += 1
        print(f"[convai] updated {name}: {old_url} -> {new_url}")

    print(f"[convai] done; updated_tools={updated}")


if __name__ == "__main__":
    main()

