#!/bin/bash
set -euo pipefail

# Input validation and environment variables
if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
  echo "Usage: SOURCE_USER=... SOURCE_PAT=... MIRROR_USER=... MIRROR_PAT=... $0 <source-repo-url> <mirror-repo-url> [work-dir]"
  exit 1
fi

SOURCE_REPO_URL="$1"
MIRROR_REPO_URL="$2"
WORKDIR="${3:-/tmp/git-mirror}"
REPO_DIR="$WORKDIR/repo-mirror"
LOGFILE="$WORKDIR/git-sync.log"
LOCKFILE="$WORKDIR/git-sync.lock"

for var in SOURCE_USER SOURCE_PAT MIRROR_USER MIRROR_PAT; do
  if [[ -z "${!var:-}" ]]; then
    echo "[ERROR] Missing required environment variable: $var"
    exit 1
  fi
done

inject_auth() {
  local user="$1"
  local token="$2"
  local url="$3"
  echo "$url" | sed -E "s#https://#https://${user}:${token}@#"
}

AUTH_SOURCE_REPO_URL=$(inject_auth "$SOURCE_USER" "$SOURCE_PAT" "$SOURCE_REPO_URL")
AUTH_MIRROR_REPO_URL=$(inject_auth "$MIRROR_USER" "$MIRROR_PAT" "$MIRROR_REPO_URL")

mkdir -p "$WORKDIR"
exec 200>"$LOCKFILE"
flock -n 200 || { echo "[ERROR] Another sync is already in progress. Exiting."; exit 1; }

echo "[INFO] Starting sync at $(date)" | tee -a "$LOGFILE"

if [ ! -d "$REPO_DIR" ]; then
  git clone --mirror "$AUTH_SOURCE_REPO_URL" "$REPO_DIR"
else
  cd "$REPO_DIR"
  git remote update --prune
fi

cd "$REPO_DIR"
git remote set-url origin "$AUTH_MIRROR_REPO_URL"
git push -v origin --all | tee -a "$LOGFILE"
git push -v origin --tags | tee -a "$LOGFILE"
git log -n5 --pretty=format:"%h %ad %s" --date=short | tee -a "$LOGFILE"
echo "[SUCCESS] Sync complete at $(date)" | tee -a "$LOGFILE"
