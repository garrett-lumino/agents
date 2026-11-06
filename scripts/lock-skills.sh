#!/usr/bin/env bash
# Make vendored and self-written skills read-only, so agents that can patch
# skills in place (Hermes skill_manage, which writes atomically into the
# directory) can't silently rewrite reviewed files. skills/ itself and
# SOURCES.md stay writable so vendor-skill.sh can add new skills.
# Usage: lock-skills.sh lock|unlock   (unlock before editing or `git pull`)
set -euo pipefail

SKILLS="$(cd "$(dirname "$0")/.." && pwd)/skills"

main() {
  local dir
  case "${1:-}" in
    lock) mode=a-w ;;
    unlock) mode=u+w ;;
    *) printf 'usage: %s lock|unlock\n' "$0" >&2; exit 1 ;;
  esac
  for dir in "$SKILLS"/*/; do
    [ -d "$dir" ] && chmod -R "$mode" "$dir"
  done
  printf 'skills: %sed\n' "$1"
}

main "$@"
