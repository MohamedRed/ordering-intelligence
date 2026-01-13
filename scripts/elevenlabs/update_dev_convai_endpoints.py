#!/usr/bin/env python3
import os
import sys
from typing import Any, Dict, List

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
    from elevenlabs.types.conversation_initiation_client_data_webhook import (  # type: ignore
        ConversationInitiationClientDataWebhook,
    )
    from elevenlabs.types.tool_request_model import ToolRequestModel  # type: ignore
    from elevenlabs.types.tool_request_model_tool_config import ToolRequestModelToolConfig_Webhook  # type: ignore

    return ElevenLabs, ConversationInitiationClientDataWebhook, ToolRequestModel, ToolRequestModelToolConfig_Webhook


def replace_urls(obj, old_bases, new_base):
    if isinstance(obj, str):
        out = obj
        for old in old_bases:
            if old:
                out = out.replace(old, new_base)
        return out
    if isinstance(obj, list):
        return [replace_urls(v, old_bases, new_base) for v in obj]
    if isinstance(obj, dict):
        return {k: replace_urls(v, old_bases, new_base) for k, v in obj.items()}
    return obj


def main():
    api_key = _env("ELEVENLABS_API_KEY")
    webhook_url = _env("CONVAI_WEBHOOK_URL")
    webhook_secret = _env("CONVAI_WEBHOOK_SECRET")
    agent_tools_lb_base = _env("AGENT_TOOLS_LB_BASE").rstrip("/")

    ElevenLabs, ConvInitWebhook, ToolRequestModel, WebhookCfg = _import_elevenlabs_sdk()
    client = ElevenLabs(api_key=api_key)

    # Common old bases we might have configured previously.
    old_bases = [
        "https://agent-tools-230152279015.us-central1.run.app",
        "https://agent-tools-f2qwyitacq-uc.a.run.app",
        os.getenv("AGENT_TOOLS_OLD_BASE", "").strip(),
    ]

    # 1) Update workspace conversation-init webhook URL (preserve headers + ensure secret).
    settings = client.conversational_ai.settings.get()
    existing = getattr(settings, "conversation_initiation_client_data_webhook", None)
    existing_headers = getattr(existing, "request_headers", None) if existing else None
    headers: Dict[str, Any] = dict(existing_headers or {})
    headers.setdefault("Content-Type", "application/json")
    headers["x-elevenlabs-conversation-init-secret"] = webhook_secret

    try:
        client.conversational_ai.settings.update(
            conversation_initiation_client_data_webhook=ConvInitWebhook(url=webhook_url, request_headers=headers)
        )
    except Exception as exc:  # noqa: BLE001
        print(f"[convai] settings update failed err={exc}", file=sys.stderr)
        raise SystemExit(1) from exc

    print(f"[convai] updated conversation-init webhook url -> {webhook_url}")

    # 2) Update any webhook tools still pointing to old agent-tools base URL(s).
    tools = client.conversational_ai.tools.list().tools

    updated = 0
    for tool in tools:
        tool_id = getattr(tool, "id", "")
        tc = getattr(tool, "tool_config", None)
        if tc is None or getattr(tc, "type", None) != "webhook":
            continue
        api_schema = getattr(tc, "api_schema", None)
        if api_schema is None:
            continue

        schema_dict = api_schema.model_dump(exclude_none=True)  # type: ignore[attr-defined]
        new_schema = replace_urls(schema_dict, old_bases, agent_tools_lb_base)
        if new_schema == schema_dict:
            continue

        tc_dict: Dict[str, Any] = tc.model_dump(exclude_none=True)  # type: ignore[attr-defined]
        tc_dict["api_schema"] = new_schema

        req = ToolRequestModel(tool_config=WebhookCfg(**tc_dict))
        try:
            client.conversational_ai.tools.update(tool_id, request=req)
        except Exception as exc:  # noqa: BLE001
            name = getattr(tc, "name", "")
            print(f"[convai] tool update failed id={tool_id} name={name} err={exc}", file=sys.stderr)
            continue

        updated += 1
        name = getattr(tc, "name", "")
        print(f"[convai] updated tool url(s) id={tool_id} name={name}")

    print(f"[convai] done; updated_tools={updated}")
    return

if __name__ == "__main__":
    main()

