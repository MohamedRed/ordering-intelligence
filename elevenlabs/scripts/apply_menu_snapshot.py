#!/usr/bin/env python3
"""
Fetches a menu snapshot from the Order Service and injects it into ElevenLabs
agent prompts between MENU_SNAPSHOT markers. Idempotent: rerunning replaces
the previous block.
"""

import json
import os
import re
import sys
from urllib import request, error


ORDER_SERVICE_URL = os.getenv("ORDER_SERVICE_URL", "http://localhost:8082")
STORE_ID = os.getenv("STORE_ID", "demo-store")
AGENT_CONFIGS = [
    path.strip()
    for path in os.getenv(
        "AGENT_CONFIGS",
        "agent_configs/Order-taker.json",
    ).split(",")
    if path.strip()
]

START = "<!-- MENU_SNAPSHOT_START -->"
END = "<!-- MENU_SNAPSHOT_END -->"


def fetch_snapshot() -> dict:
    url = f"{ORDER_SERVICE_URL}/stores/{STORE_ID}/menu/snapshot"
    try:
        with request.urlopen(url, timeout=10) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except error.URLError as exc:
        sys.stderr.write(f"Failed to fetch menu snapshot from {url}: {exc}\n")
        sys.exit(1)


def format_snapshot(snapshot: dict) -> str:
    items = snapshot.get("items", [])[:120]
    lines = [
        "# Menu snapshot (synced from order service)",
        f"store: {snapshot.get('storeId', 'unknown')}",
        f"updated: {snapshot.get('updated', '')}",
    ]
    for item in items:
        name = item.get("name", "unknown")
        cat = item.get("category") or item.get("type") or "item"
        price = item.get("priceCents", 0) / 100
        mods = item.get("modifiers") or []
        mods_str = f" | mods: {', '.join(mods)}" if mods else ""
        lines.append(f"- {name} ({cat}) ${price:.2f}{mods_str}")
    return "\n".join(lines)


def inject_prompt(path: str, snapshot_text: str) -> None:
    if not os.path.exists(path):
        sys.stderr.write(f"Config not found: {path}\n")
        sys.exit(1)

    with open(path, "r", encoding="utf-8") as f:
        config = json.load(f)

    try:
        prompt = config["conversation_config"]["agent"]["prompt"]["prompt"]
    except KeyError:
        sys.stderr.write(f"Prompt field not found in {path}\n")
        sys.exit(1)

    block = f"{START}\n{snapshot_text}\n{END}"
    pattern = re.compile(f"{START}.*?{END}", re.DOTALL)

    if START in prompt and END in prompt:
        prompt = pattern.sub(block, prompt)
    else:
        prompt = prompt.rstrip() + "\n\n" + block

    config["conversation_config"]["agent"]["prompt"]["prompt"] = prompt

    with open(path, "w", encoding="utf-8") as f:
        json.dump(config, f, ensure_ascii=True, indent=4)
        f.write("\n")

    print(f"Injected menu snapshot into {path} ({len(snapshot_text.splitlines())} lines)")


def main() -> None:
    snapshot = fetch_snapshot()
    formatted = format_snapshot(snapshot)
    for path in AGENT_CONFIGS:
        inject_prompt(path, formatted)


if __name__ == "__main__":
    main()
