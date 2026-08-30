#!/bin/bash
set -euo pipefail

REPO_DIR="/Users/thirtyone/Documents/Obsidian Vault"
SSH_KEY="$HOME/.ssh/id_ed25519_personal"

cd "$REPO_DIR"

if [ -n "$(git status --porcelain)" ]; then
  git add -A
  git commit -m "Auto-sync $(date '+%Y-%m-%d %H:%M %Z')"
fi

export GIT_SSH_COMMAND="ssh -i $SSH_KEY -o IdentitiesOnly=yes"
git push -u origin main
