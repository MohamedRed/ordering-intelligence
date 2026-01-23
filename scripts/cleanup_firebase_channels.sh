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

for site in "${SITES[@]}"; do
  mapfile -t delete_channels < <(
    firebase hosting:channel:list --project "$PROJECT" --site "$site" --json | \
      python3 - "$PREFIX" "$KEEP" "${RETAIN[@]}" <<'PY'
import sys
import json
from datetime import datetime, timezone

prefix = sys.argv[1]
keep = int(sys.argv[2])
retain = {arg for arg in sys.argv[3:] if arg}
raw = sys.stdin.read().strip()
if not raw:
    sys.exit(0)

try:
    data = json.loads(raw)
except json.JSONDecodeError:
    sys.exit(0)

if isinstance(data, dict) and data.get("status") == "error":
    sys.stderr.write(str(data.get("error", "firebase channel list failed")) + "\n")
    sys.exit(1)

channels = []

def collect(obj):
    if isinstance(obj, dict):
        name = obj.get("name") if isinstance(obj.get("name"), str) else ""
        if "channelId" in obj or "/channels/" in name:
            channels.append(obj)
            return
        for value in obj.values():
            collect(value)
    elif isinstance(obj, list):
        for value in obj:
            collect(value)

collect(data)

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
    time_value = channel.get("updateTime") or channel.get("expireTime") or channel.get("createTime")
    try:
        parsed = datetime.fromisoformat(time_value.replace("Z", "+00:00")) if time_value else None
    except ValueError:
        parsed = None
    entries.append((parsed or datetime.min.replace(tzinfo=timezone.utc), channel_id))

entries.sort(key=lambda item: item[0], reverse=True)
for _, channel_id in entries[keep:]:
    print(channel_id)
PY
  )

  if [[ ${#delete_channels[@]} -eq 0 ]]; then
    echo "No channels to prune for $site."
    continue
  fi

  echo "Pruning ${#delete_channels[@]} channels for $site."
  for channel_id in "${delete_channels[@]}"; do
    firebase hosting:channel:delete "$channel_id" --project "$PROJECT" --site "$site" --force
  done

  echo "Finished pruning channels for $site."
done
