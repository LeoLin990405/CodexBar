#!/usr/bin/env bash
# CodexBar auto-deploy: polls latest "Release macOS App" success run on
# feat/trae-dollar-usage, swaps in /Applications/CodexBar.app when a
# newer commit ships an artifact. Designed to be invoked by launchd.
#
# Idempotent: writes ~/.codexbar/auto-deploy-state.json holding the
# last-installed run id; exits 0 if nothing new.
set -euo pipefail

REPO="LeoLin990405/CodexBar"
WORKFLOW="Release macOS App"
BRANCH="feat/trae-dollar-usage"
STATE_DIR="$HOME/.codexbar"
STATE_FILE="$STATE_DIR/auto-deploy-state.json"
LOG_FILE="$STATE_DIR/auto-deploy.log"
APP_PATH="/Applications/CodexBar.app"

mkdir -p "$STATE_DIR"
exec >> "$LOG_FILE" 2>&1
echo "[$(date '+%Y-%m-%d %H:%M:%S')] checking $REPO@$BRANCH for new $WORKFLOW success"

if ! command -v gh >/dev/null 2>&1; then
  echo "gh CLI missing; aborting"; exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "jq missing; aborting"; exit 1
fi

LATEST=$(gh run list \
  --workflow "$WORKFLOW" \
  --branch "$BRANCH" \
  --status success \
  --limit 1 \
  -R "$REPO" \
  --json databaseId,headSha,displayTitle,createdAt \
  --jq '.[0]')

if [ -z "$LATEST" ] || [ "$LATEST" = "null" ]; then
  echo "no successful run found"; exit 0
fi

RUN_ID=$(echo "$LATEST" | jq -r .databaseId)
SHA=$(echo "$LATEST" | jq -r .headSha)
TITLE=$(echo "$LATEST" | jq -r .displayTitle)

LAST_RUN=""
if [ -f "$STATE_FILE" ]; then
  LAST_RUN=$(jq -r '.last_run_id // ""' "$STATE_FILE" 2>/dev/null || echo "")
fi

if [ "$RUN_ID" = "$LAST_RUN" ]; then
  echo "already installed run $RUN_ID ($SHA); skip"; exit 0
fi

echo "new artifact: run=$RUN_ID sha=$SHA title=$TITLE"

TMPDIR=$(mktemp -d -t codexbar-deploy)
trap "rm -rf $TMPDIR" EXIT

gh run download "$RUN_ID" -R "$REPO" -D "$TMPDIR" >/dev/null

ZIP=$(find "$TMPDIR" -name '*.zip' | head -1)
if [ -z "$ZIP" ]; then
  echo "no zip in artifact; abort"; exit 1
fi

pkill -x CodexBar 2>/dev/null || true
sleep 1

BACKUP="/Applications/CodexBar-prev-$(date +%Y%m%d-%H%M).app"
if [ -d "$APP_PATH" ]; then
  mv "$APP_PATH" "$BACKUP"
  echo "backup: $BACKUP"
fi

unzip -q -o "$ZIP" -d /Applications/
xattr -dr com.apple.quarantine "$APP_PATH" 2>/dev/null || true
open -n "$APP_PATH"
echo "installed run $RUN_ID"

# Trim backups older than 7 days to avoid /Applications bloat
find /Applications -maxdepth 1 -name 'CodexBar-prev-*.app' -mtime +7 -prune -exec rm -rf {} \; 2>/dev/null || true

cat > "$STATE_FILE" <<JSON
{
  "last_run_id": "$RUN_ID",
  "last_sha": "$SHA",
  "last_title": $(jq -Rs . <<< "$TITLE"),
  "installed_at": "$(date '+%Y-%m-%dT%H:%M:%S%z')"
}
JSON
echo "state updated"
