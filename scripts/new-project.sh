#!/usr/bin/env bash
# Copy a project template into a target repo. Existing files are never overwritten.
# Usage: new-project.sh [--ml] <target-dir>
#   default: templates/project      (Go/TS service: AGENTS.md, linters, Makefile)
#   --ml:    templates/ml-project   (uv Python ML project: evals, .ml gates, Makefile)
set -euo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)

usage() { printf 'usage: %s [--ml] <target-dir>\n' "$0" >&2; exit 1; }

copy_tree() {
  local src="$1" target="$2" rel
  (cd "$src" && find . -type f | sed 's|^\./||' | sort) | while IFS= read -r rel; do
    if [ -e "$target/$rel" ]; then
      printf 'skip (exists): %s\n' "$rel"
    else
      mkdir -p "$(dirname "$target/$rel")"
      cp "$src/$rel" "$target/$rel"
      printf 'added:         %s\n' "$rel"
    fi
  done
}

main() {
  local template="$REPO/templates/project"
  if [ "${1:-}" = --ml ]; then
    template="$REPO/templates/ml-project"
    shift
  fi
  [ $# -eq 1 ] || usage
  [ -d "$1" ] || { printf 'not a directory: %s\n' "$1" >&2; exit 1; }
  copy_tree "$template" "$1"
}

main "$@"
