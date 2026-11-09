#!/usr/bin/env bash
# Install this repo into ~/.claude. Safe to run repeatedly.
#   1. back up CLAUDE.md, settings.json, skills/ (first run only)
#   2. link ~/agents -> this repo
#   3. link ~/.claude/CLAUDE.md -> ~/agents/AGENTS.md
#   4. link each vendored skill into ~/.claude/skills/
#   5. merge claude/settings.json into ~/.claude/settings.json
#   6. make skill folders read-only (scripts/lock-skills.sh)
#   7. wire the shared AI memory vault into every harness (scripts/install-memory.sh)
set -euo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)
AGENTS="$HOME/agents"
CLAUDE="$HOME/.claude"
MARKER="$CLAUDE/.agents-backup"

say() { printf '%s\n' "$*"; }

backup_once() {
  [ -f "$MARKER" ] && { say "backup: already done ($(cat "$MARKER"))"; return 0; }
  local dest
  dest="$CLAUDE/backup-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$dest"
  local item
  for item in CLAUDE.md settings.json skills; do
    [ -e "$CLAUDE/$item" ] || [ -L "$CLAUDE/$item" ] || continue
    cp -RP "$CLAUDE/$item" "$dest/"
  done
  printf '%s\n' "$dest" >"$MARKER"
  say "backup: $dest"
}

# ensure_link <target> <link>: create, accept if already correct, refuse otherwise.
ensure_link() {
  local target="$1" link="$2"
  if [ -L "$link" ] && [ "$(readlink "$link")" = "$target" ]; then
    say "ok:     $link"
  elif [ -e "$link" ] || [ -L "$link" ]; then
    say "SKIP:   $link exists and is not -> $target (move it aside, then re-run)" >&2
    return 1
  else
    ln -s "$target" "$link"
    say "linked: $link -> $target"
  fi
}

# Remove our skill links whose target no longer exists (renamed/removed skills).
prune_skill_links() {
  local link
  for link in "$CLAUDE"/skills/*; do
    [ -L "$link" ] || continue
    case "$(readlink "$link")" in "$AGENTS/skills/"*) ;; *) continue ;; esac
    [ -e "$link" ] || { rm "$link"; say "pruned: $link"; }
  done
}

link_skills() {
  local dir name
  mkdir -p "$CLAUDE/skills"
  prune_skill_links
  for dir in "$REPO"/skills/*/; do
    [ -d "$dir" ] || continue
    name=$(basename "$dir")
    ensure_link "$AGENTS/skills/$name" "$CLAUDE/skills/$name" || true
  done
}

main() {
  mkdir -p "$CLAUDE"
  backup_once
  [ "$REPO" = "$AGENTS" ] || ensure_link "$REPO" "$AGENTS"
  ensure_link "$AGENTS/AGENTS.md" "$CLAUDE/CLAUDE.md" || true
  link_skills
  "$REPO/scripts/merge-settings.sh"
  "$REPO/scripts/lock-skills.sh" lock
  "$REPO/scripts/install-memory.sh"
}

main "$@"
