#!/usr/bin/env python3
"""
Create a versioning branch for an existing ElevenLabs Conversational AI agent.

This is for ElevenLabs *agent versioning* (branches/versions/traffic), not for cloning
an agent into a brand-new agent_id.

Example (branch from latest Main version):
  ELEVENLABS_API_KEY=... python3 elevenlabs/scripts/create_agent_branch.py \\
    --agent-id agent_7201kbfs3pbpe1tsv4dmakk1207q \\
    --name "experiment/personalization" \\
    --description "Try customerName + topReorders greeting flow" \\
    --output elevenlabs/tmp_local_current/order-taker-branch.json

Notes:
  - The exact branch endpoints have changed across ElevenLabs releases.
    This script tries a small set of likely endpoints and fails with a clear error
    if none work.
  - If your agent doesn't have versioning enabled yet, this script will attempt to
    enable it via PATCH /v1/convai/agents/{agent_id} with enable_versioning_if_not_enabled=true.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from dataclasses import dataclass
from typing import Any, Dict, List, Optional, Tuple
from urllib import error, request


DEFAULT_API_BASE_URL = "https://api.elevenlabs.io"


def _api_key() -> str:
    key = (os.getenv("ELEVENLABS_API_KEY") or os.getenv("XI_API_KEY") or "").strip()
    if key:
        return key

    # Fallback: GCP Secret Manager (preferred in this repo)
    # Defaults match our GCP project/secret naming conventions.
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
            try:
                return json.loads(raw)
            except json.JSONDecodeError as exc:
                raise RuntimeError(f"Invalid JSON from {method} {path}: {exc}: {raw[:200]}") from exc
    except error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"ElevenLabs {method} {path} failed status={exc.code} body={detail[:500]}") from exc
    except error.URLError as exc:
        raise RuntimeError(f"ElevenLabs {method} {path} failed: {exc}") from exc


def _try_request_json(
    *,
    base_url: str,
    api_key: str,
    method: str,
    paths: List[str],
    body: Any | None = None,
) -> Tuple[str, Any]:
    last_err: Optional[Exception] = None
    for path in paths:
        try:
            return path, _request_json(base_url=base_url, api_key=api_key, method=method, path=path, body=body)
        except Exception as exc:  # noqa: BLE001
            last_err = exc
            continue
    raise RuntimeError(
        "No candidate endpoint worked. Last error: " + (str(last_err) if last_err else "unknown")
    ) from last_err


def _enable_versioning_if_needed(*, base_url: str, api_key: str, agent_id: str) -> None:
    # Best-effort: the versioning docs describe this field, but older servers may reject it.
    try:
        _request_json(
            base_url=base_url,
            api_key=api_key,
            method="PATCH",
            path=f"/v1/convai/agents/{agent_id}",
            body={"enable_versioning_if_not_enabled": True},
        )
    except Exception as exc:  # noqa: BLE001
        # Non-fatal; user might have versioning already enabled, or this field may not be supported.
        sys.stderr.write(f"warn: could not enable versioning automatically: {exc}\n")


@dataclass(frozen=True)
class BranchInfo:
    branch_id: str
    name: str
    version_records: List[Dict[str, Any]]

    @property
    def latest_version_id(self) -> Optional[str]:
        if not self.version_records:
            return None

        def sort_key(v: Dict[str, Any]) -> Any:
            # Observed fields:
            # - time_committed_secs (int)
            # - created_at / createdAt (int)
            return (
                v.get("time_committed_secs")
                or v.get("timeCommittedSecs")
                or v.get("created_at")
                or v.get("createdAt")
                or v.get("created")
                or 0
            )

        latest = sorted(self.version_records, key=sort_key)[-1]
        return str(latest.get("id") or latest.get("version_id") or latest.get("versionId") or "").strip() or None


def _normalize_branches(payload: Any) -> List[BranchInfo]:
    # Observed API shapes:
    # - {"meta": {...}, "results": [ {branch...}, ... ]}
    # - {"branches": [ {branch...}, ... ]}
    # - {branch...} (single branch)
    # - [ {branch...}, ... ]
    raw_branches: List[Any]
    if isinstance(payload, dict):
        if isinstance(payload.get("branches"), list):
            raw_branches = payload["branches"]
        elif isinstance(payload.get("results"), list):
            raw_branches = payload["results"]
        elif "id" in payload and "name" in payload:
            raw_branches = [payload]
        else:
            raise RuntimeError(f"Unexpected branches payload keys: {sorted(list(payload.keys()))[:20]}")
    elif isinstance(payload, list):
        raw_branches = payload
    else:
        raise RuntimeError(f"Unexpected branches payload type: {type(payload).__name__}")

    branches: List[BranchInfo] = []
    for b in raw_branches:
        if not isinstance(b, dict):
            continue
        branch_id = str(b.get("id") or b.get("branch_id") or b.get("branchId") or "").strip()
        name = str(b.get("name") or "").strip()
        # Some endpoints return versions, others return most_recent_versions.
        versions_raw = b.get("versions")
        most_recent_versions_raw = b.get("most_recent_versions") or b.get("mostRecentVersions")
        version_records: List[Dict[str, Any]] = []
        if isinstance(versions_raw, list):
            version_records = [v for v in versions_raw if isinstance(v, dict)]
        elif isinstance(most_recent_versions_raw, list):
            version_records = [v for v in most_recent_versions_raw if isinstance(v, dict)]

        if branch_id:
            branches.append(BranchInfo(branch_id=branch_id, name=name, version_records=version_records))
    return branches


def _find_main_branch(branches: List[BranchInfo]) -> Optional[BranchInfo]:
    for b in branches:
        if b.name.strip().lower() == "main":
            return b
    # Some APIs might name the main branch differently; fall back to an id convention.
    for b in branches:
        if b.branch_id.strip().lower().endswith("_main"):
            return b
    return branches[0] if branches else None


def _list_branches(*, base_url: str, api_key: str, agent_id: str) -> Tuple[str, List[BranchInfo]]:
    path, payload = _try_request_json(
        base_url=base_url,
        api_key=api_key,
        method="GET",
        paths=[
            f"/v1/convai/agents/{agent_id}/branches",
            f"/v1/convai/agents/{agent_id}/branches/list",
        ],
    )
    return path, _normalize_branches(payload)


def _get_branch(*, base_url: str, api_key: str, agent_id: str, branch_id: str) -> Tuple[str, BranchInfo]:
    path, payload = _try_request_json(
        base_url=base_url,
        api_key=api_key,
        method="GET",
        paths=[
            f"/v1/convai/agents/{agent_id}/branches/{branch_id}",
            f"/v1/convai/agents/{agent_id}/branches/get?branch_id={branch_id}",
        ],
    )
    branches = _normalize_branches(payload.get("branches") if isinstance(payload, dict) and "branches" in payload else payload)
    # For get, expect exactly one, but handle common shapes.
    for b in branches:
        if b.branch_id == branch_id:
            return path, b
    if branches:
        return path, branches[0]
    raise RuntimeError("Branch details response did not include a branch record")


def _create_branch(
    *,
    base_url: str,
    api_key: str,
    agent_id: str,
    parent_version_id: str,
    name: str,
    description: str,
) -> Tuple[str, Dict[str, Any]]:
    body = {
        "parent_version_id": parent_version_id,
        "name": name,
        "description": description,
    }
    path, payload = _try_request_json(
        base_url=base_url,
        api_key=api_key,
        method="POST",
        paths=[
            f"/v1/convai/agents/{agent_id}/branches/create",
            f"/v1/convai/agents/{agent_id}/branches",
        ],
        body=body,
    )
    if not isinstance(payload, dict):
        raise RuntimeError(f"Unexpected create-branch response type: {type(payload).__name__}")
    return path, payload


def _write_json(path: str, obj: Any, *, force: bool) -> None:
    if os.path.exists(path) and not force:
        raise RuntimeError(f"Refusing to overwrite existing file: {path} (use --force)")
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(obj, f, ensure_ascii=True, indent=4)
        f.write("\n")


def main() -> None:
    parser = argparse.ArgumentParser(description="Create an ElevenLabs agent versioning branch.")
    parser.add_argument("--agent-id", required=True, help="Agent id to branch (agent_...).")
    parser.add_argument("--name", required=True, help="Branch name (e.g., experiment/new-greeting).")
    parser.add_argument("--description", default="", help="Optional branch description.")
    parser.add_argument(
        "--parent-version-id",
        default="",
        help="Parent version id from Main branch (agtvrsn_...). If omitted, auto-detected from Main.",
    )
    parser.add_argument("--api-base-url", default=None, help="Override ElevenLabs API base URL.")
    parser.add_argument("--skip-enable-versioning", action="store_true", help="Do not attempt to enable versioning.")
    parser.add_argument("--output", default="", help="Write created branch info JSON to this path.")
    parser.add_argument("--force", action="store_true", help="Overwrite --output if it exists.")
    parser.add_argument("--dry-run", action="store_true", help="Resolve parent version id then print and exit.")
    args = parser.parse_args()

    api_key = _api_key()
    if not api_key:
        raise SystemExit("ELEVENLABS_API_KEY (or XI_API_KEY) is not set.")
    base_url = _api_base_url(args.api_base_url)

    if not args.skip_enable_versioning:
        _enable_versioning_if_needed(base_url=base_url, api_key=api_key, agent_id=args.agent_id)

    parent_version_id = args.parent_version_id.strip()
    if not parent_version_id:
        list_path, branches = _list_branches(base_url=base_url, api_key=api_key, agent_id=args.agent_id)
        if not branches:
            raise RuntimeError(f"No branches returned from {list_path}; cannot infer Main parent version.")
        main_branch = _find_main_branch(branches)
        if not main_branch:
            raise RuntimeError("Could not identify Main branch.")
        # If list response omitted versions, fetch branch details.
        if not main_branch.version_records:
            _, main_branch = _get_branch(
                base_url=base_url, api_key=api_key, agent_id=args.agent_id, branch_id=main_branch.branch_id
            )
        parent_version_id = (main_branch.latest_version_id or "").strip()
        if not parent_version_id:
            raise RuntimeError("Could not infer parent_version_id from Main branch versions.")

    if args.dry_run:
        print(
            json.dumps(
                {
                    "agent_id": args.agent_id,
                    "branch_name": args.name,
                    "description": args.description,
                    "parent_version_id": parent_version_id,
                },
                indent=2,
            )
        )
        return

    create_path, created = _create_branch(
        base_url=base_url,
        api_key=api_key,
        agent_id=args.agent_id,
        parent_version_id=parent_version_id,
        name=args.name,
        description=args.description,
    )

    created_branch_id = str(created.get("created_branch_id") or created.get("branch_id") or created.get("id") or "").strip()
    created_version_id = str(created.get("created_version_id") or created.get("version_id") or "").strip()

    info = {
        "agent_id": args.agent_id,
        "branch_id": created_branch_id,
        "version_id": created_version_id,
        "parent_version_id": parent_version_id,
        "name": args.name,
        "description": args.description,
        "create_endpoint": create_path,
        "api_base_url": base_url,
        "raw_response": created,
    }

    if args.output:
        _write_json(args.output, info, force=args.force)

    print(f"Created branch on agent {args.agent_id}")
    print(f"- branch_id: {created_branch_id or '(see raw_response)'}")
    print(f"- version_id: {created_version_id or '(see raw_response)'}")
    if args.output:
        print(f"- wrote: {args.output}")


if __name__ == "__main__":
    main()
