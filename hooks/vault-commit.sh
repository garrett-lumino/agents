#!/bin/sh
# Commit any changes in the AI memory vault to its local git history.
# Runs as a Claude Code SessionEnd hook and from launchd every 15 minutes
# (scripts/install-memory.sh), so writes by any AI tool get versioned.
VAULT="${AGENTS_VAULT:-$HOME/dev/obsidian}"
input=$(cat)
[ -d "$VAULT/.git" ] || exit 0
# Never run code the repo itself defines (hooks, fsmonitor, signing program):
# other tools can write in the vault, and this runs unattended.
vgit() {
  git -C "$VAULT" -c core.hooksPath=/dev/null -c core.fsmonitor=false \
    -c commit.gpgSign=false -c user.name="AI memory" -c user.email=noreply@localhost "$@"
}
[ -n "$(vgit status --porcelain)" ] || exit 0

source=scheduled
transcript=$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)
if [ -n "$transcript" ]; then
  source=$(basename -- "$(dirname -- "$transcript")")
  source=${source#"$(printf '%s' "$HOME/dev/github/" | tr '/' '-')"}
  source=${source#-}
fi

vgit add -A &&
  vgit commit -q --no-verify -m "memory: $source $(date -u +%Y-%m-%dT%H:%M:%SZ)" >/dev/null 2>&1
exit 0
