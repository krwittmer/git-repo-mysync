# Syncing Git Repository Automation

## Introduction
Syncing Git repositories between different environments — such as GitHub.com (cloud) and GitHub Enterprise Server (on-prem) — is a common but often underestimated challenge. This article explores best practices, popular tools, pitfalls, and provides a production-ready Bash script to automate one-way Git repo synchronization using secure token-based authentication.

## Approach Comparison
There are several approaches developers have used to sync Git repos:

- Native Git CLI with `--mirror`, `--all`, and `--tags`
- Tools like `gitr`, GitHub Actions, or GitHub Webhooks
- Git post-receive hooks
- Python Git wrappers like `GitPython`, `pygit2`, or `dulwich`

**Conclusion**: While some tools are useful, nothing matches the flexibility and power of the Git CLI, especially when run directly from a shell or orchestrated via Python's subprocess module.

## Challenges with Python Git Libraries
Popular Python libraries like `GitPython` and `pygit2` are powerful, but they lack full support for complex Git operations like `--mirror` push or `--prune` fetch. For example:

```python
from git import Repo
repo = Repo.clone_from("https://github.com/source/repo.git", "/tmp/repo", mirror=True)
repo.remotes.origin.push(mirror=True)  # Not supported
```

Instead, use Python to invoke Git directly:

```python
import subprocess
subprocess.run(["git", "clone", "--mirror", source_url, target_dir])
```

## Secure Authentication Using PATs
Using Personal Access Tokens (PATs) securely is essential. The safest methods include:

- Exporting tokens as environment variables
- Injecting them dynamically into HTTPS URLs
- Avoiding hardcoding or logging sensitive credentials

**Tip**: Never include PATs in code or URLs directly. Prefer `GITHUB_USER` and `GITHUB_PAT` stored in your shell or CI/CD secret store.

## Production-Grade Bash Script for Syncing Git Repositories
Below is a final, production-ready Bash script that supports syncing between two Git repos with separate credentials for cloud (e.g., GitHub.com) and on-prem (e.g., GitHub Enterprise Server):

### Final Script: `git-repo-sync.sh`
```bash
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
```

## Conclusion
Syncing Git repositories across environments is a common requirement, and the most robust approach uses the Git CLI, scripted securely with environment-based authentication. Python can serve as an orchestrator but should defer to native Git when depth of functionality and reliability matter most.