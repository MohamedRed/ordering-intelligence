#!/usr/bin/env python3
"""
Unarchive the most recently updated archived branches for an ElevenLabs Conversational AI agent.

Uses:
- Google Secret Manager (GCP) to fetch ELEVENLABS_API_KEY (default secret: elevenlabs-api-key)
- Direct ElevenLabs HTTP API calls for branch listing/update (SDK may not expose branch endpoints in all versions)

Example:
  python3 elevenlabs/scripts/unarchive_recent_archived_branches.py \
    --agent-id agent_7201kbfs3pbpe1tsv4dmakk1207q \
    --count 2
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from dataclasses import dataclass
from typing import Any, Dict, List, Optional, Tuple

import re
import subprocess
from urllib import error, request

import google.auth  # type: ignore
from google.cloud import secretmanager  # type: ignore


DEFAULT_API_BASE_URL = "https://api.elevenlabs.io"


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


def _api_base_url(override: Optional[str]) -> str:
    base = (override or os.getenv("ELEVENLABS_API_BASE_URL") or DEFAULT_API_BASE_URL).strip()
    return re.sub(r"/+$", "", base)


def _request_json(*, base_url: str, api_key: str, method: str, path: str, body: Any | None = None) -> Any:
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
        raise RuntimeError(f"ElevenLabs {method} {path} failed status={exc.code} body={detail[:800]}") from exc


def _try_request_json(*, base_url: str, api_key: str, method: str, paths: List[str], body: Any | None = None) -> Tuple[str, Any]:
    last_err: Optional[Exception] = None
    for path in paths:
        try:
            return path, _request_json(base_url=base_url, api_key=api_key, method=method, path=path, body=body)
        except Exception as exc:  # noqa: BLE001
            last_err = exc
            continue
    raise RuntimeError("No candidate endpoint worked. Last error: " + (str(last_err) if last_err else "unknown")) from last_err


def _to_dict(obj: Any) -> Dict[str, Any]:
    if obj is None:
        return {}
    if isinstance(obj, dict):
        return obj
    if hasattr(obj, "model_dump"):
        return obj.model_dump()  # pydantic v2
    if hasattr(obj, "dict"):
        return obj.dict()  # pydantic v1
    if hasattr(obj, "__dict__"):
        return dict(obj.__dict__)
    return {}


def _version_sort_key(v: Any) -> int:
    d = _to_dict(v)
    for k in (
        "time_committed_secs",
        "timeCommittedSecs",
        "created_at",
        "createdAt",
        "created",
        "time_committed",
        "timeCommitted",
    ):
        raw = d.get(k)
        try:
            if raw is None:
                continue
            return int(raw)
        except Exception:  # noqa: BLE001
            continue
    return 0


def _branch_sort_key(b: Any) -> int:
    d = _to_dict(b)
    for k in ("last_committed_at", "lastCommittedAt", "time_committed_secs", "timeCommittedSecs"):
        raw = d.get(k)
        try:
            if raw is not None:
                return int(raw)
        except Exception:  # noqa: BLE001
            pass
    versions = d.get("versions") or d.get("most_recent_versions") or d.get("mostRecentVersions") or []
    if isinstance(versions, list) and versions:
        return max(_version_sort_key(v) for v in versions)
    return int(d.get("created_at") or d.get("createdAt") or 0 or 0)


@dataclass(frozen=True)
class BranchRow:
    id: str
    name: str
    archived: bool
    version_count: int
    latest_version_ts: int


def _extract_branch_row(b: Any) -> BranchRow:
    d = _to_dict(b)
    bid = str(d.get("id") or d.get("branch_id") or d.get("branchId") or "").strip()
    name = str(d.get("name") or "").strip()
    archived = bool(d.get("archived") or d.get("is_archived") or d.get("isArchived") or False)
    versions = d.get("versions") or d.get("most_recent_versions") or d.get("mostRecentVersions") or []
    version_count = len(versions) if isinstance(versions, list) else 0
    latest_ts = _branch_sort_key(d)
    return BranchRow(id=bid, name=name, archived=archived, version_count=version_count, latest_version_ts=latest_ts)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--agent-id", required=True)
    ap.add_argument("--count", type=int, default=2)
    ap.add_argument("--gcp-project-id", default=os.getenv("GOOGLE_CLOUD_PROJECT", ""))
    ap.add_argument("--secret-id", default="elevenlabs-api-key")
    ap.add_argument("--api-base-url", default=None)
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    project_id = _get_gcp_project_id(args.gcp_project_id)
    api_key = _read_secret(project_id=project_id, secret_id=args.secret_id, version="latest")
    if not api_key:
        raise SystemExit(f"Secret {args.secret_id!r} in project {project_id!r} is empty.")

    base_url = _api_base_url(args.api_base_url)

    _, payload = _try_request_json(
        base_url=base_url,
        api_key=api_key,
        method="GET",
        paths=[
            f"/v1/convai/agents/{args.agent_id}/branches?include_archived=true",
            f"/v1/convai/agents/{args.agent_id}/branches?include_archived=1",
            f"/v1/convai/agents/{args.agent_id}/branches/list?include_archived=true",
            f"/v1/convai/agents/{args.agent_id}/branches/list?include_archived=1",
        ],
    )
    branches_raw = _to_dict(payload).get("branches")
    if not isinstance(branches_raw, list):
        branches_raw = _to_dict(payload).get("results")
    branches = branches_raw if isinstance(branches_raw, list) else (payload if isinstance(payload, list) else [])

    rows = [_extract_branch_row(b) for b in branches if _extract_branch_row(b).id]
    # Filter for archived, non-main. ("Main" is not archivable per docs.)
    archived = [r for r in rows if r.archived and r.name.strip().lower() != "main"]
    archived.sort(key=lambda r: r.latest_version_ts, reverse=True)

    n = max(0, int(args.count or 0))
    targets = archived[:n]
    if not targets:
        print(json.dumps({"status": "no_archived_branches_found", "agent_id": args.agent_id}, indent=2))
        return

    out: List[Dict[str, Any]] = []
    for r in targets:
        if args.dry_run:
            out.append({"branch_id": r.id, "name": r.name, "archived": r.archived, "action": "would_unarchive"})
            continue
        # Observed field name from list responses: is_archived (not archived).
        body = {"is_archived": False, "archived": False, "branch_id": r.id}
        _try_request_json(
            base_url=base_url,
            api_key=api_key,
            method="PATCH",
            paths=[
                f"/v1/convai/agents/{args.agent_id}/branches/{r.id}",
                f"/v1/convai/agents/{args.agent_id}/branches/update",
                f"/v1/convai/agents/{args.agent_id}/branches/{r.id}/update",
            ],
            body=body,
        )
        out.append({"branch_id": r.id, "name": r.name, "archived": False, "action": "unarchived"})

    print(json.dumps({"agent_id": args.agent_id, "updated": out}, indent=2))


if __name__ == "__main__":
    main()
