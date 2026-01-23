#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: cleanup_firebase_channels.sh --project <project-id> [--keep <count>] [--prefix <prefix>] [--retain <channel-id>] <site...>
USAGE
}

PROJECT=""
KEEP=10
PREFIX="ci-"
RETAIN=()
SITES=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)
      PROJECT="$2"
      shift 2
      ;;
    --keep)
      KEEP="$2"
      shift 2
      ;;
    --prefix)
      PREFIX="$2"
      shift 2
      ;;
    --retain)
      RETAIN+=("$2")
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      SITES+=("$1")
      shift
      ;;
  esac
done

if [[ -z "$PROJECT" || ${#SITES[@]} -eq 0 ]]; then
  usage
  exit 1
fi

TOKEN="${GCP_ACCESS_TOKEN:-}"
if [[ -z "$TOKEN" ]]; then
  TOKEN="$(gcloud auth print-access-token)"
fi

if [[ -z "$TOKEN" ]]; then
  echo "Failed to acquire access token for Firebase Hosting API." >&2
  exit 1
fi

SITES_LIST="$(printf '%s\n' "${SITES[@]}")"
RETAIN_LIST="$(printf '%s\n' "${RETAIN[@]}")"

TOKEN="$TOKEN" PROJECT="$PROJECT" KEEP="$KEEP" PREFIX="$PREFIX" \
SITES_LIST="$SITES_LIST" RETAIN_LIST="$RETAIN_LIST" \
python3 - <<'PY'
import json
import os
import sys
import urllib.parse
import urllib.request
from datetime import datetime, timezone

token = os.environ.get("TOKEN", "")
project = os.environ.get("PROJECT", "")
prefix = os.environ.get("PREFIX", "")
keep = int(os.environ.get("KEEP", "0"))
retain = {line for line in os.environ.get("RETAIN_LIST", "").splitlines() if line}
sites = [line for line in os.environ.get("SITES_LIST", "").splitlines() if line]

if not token or not project or not sites:
    sys.stderr.write("Missing token, project, or sites for Firebase channel cleanup.\n")
    sys.exit(1)

def request_json(url):
    req = urllib.request.Request(
        url,
        headers={"Authorization": f"Bearer {token}"},
    )
    with urllib.request.urlopen(req) as resp:
        payload = resp.read().decode("utf-8")
    try:
        return json.loads(payload)
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"Failed to parse JSON from {url}: {exc}") from exc

def delete_channel(site, channel_id):
    url = (
        f"https://firebasehosting.googleapis.com/v1beta1/projects/{project}"
        f"/sites/{site}/channels/{urllib.parse.quote(channel_id)}?force=true"
    )
    req = urllib.request.Request(
        url,
        method="DELETE",
        headers={"Authorization": f"Bearer {token}"},
    )
    with urllib.request.urlopen(req) as resp:
        resp.read()

def parse_time(channel):
    for key in ("updateTime", "expireTime", "createTime"):
        value = channel.get(key)
        if not value:
            continue
        try:
            return datetime.fromisoformat(value.replace("Z", "+00:00"))
        except ValueError:
            continue
    return datetime.min.replace(tzinfo=timezone.utc)

for site in sites:
    channels = []
    page_token = None
    while True:
        url = (
            f"https://firebasehosting.googleapis.com/v1beta1/projects/{project}"
            f"/sites/{site}/channels?pageSize=200"
        )
        if page_token:
            url += f"&pageToken={urllib.parse.quote(page_token)}"
        data = request_json(url)
        channels.extend(data.get("channels", []) or [])
        page_token = data.get("nextPageToken")
        if not page_token:
            break

    entries = []
    for channel in channels:
        channel_id = channel.get("channelId")
        if not channel_id:
            name = channel.get("name") if isinstance(channel.get("name"), str) else ""
            if "/channels/" in name:
                channel_id = name.split("/channels/")[-1]
        if not channel_id:
            continue
        if prefix and not channel_id.startswith(prefix):
            continue
        if channel_id in retain:
            continue
        entries.append((parse_time(channel), channel_id))

    entries.sort(key=lambda item: item[0], reverse=True)
    delete_ids = [channel_id for _, channel_id in entries[keep:]]

    if not delete_ids:
        print(f"No channels to prune for {site}.")
        continue

    print(f"Pruning {len(delete_ids)} channels for {site}.")
    for channel_id in delete_ids:
        delete_channel(site, channel_id)
    print(f"Finished pruning channels for {site}.")
PY
