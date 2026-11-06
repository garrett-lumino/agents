#!/usr/bin/env bash
# Vendor one skill directory from a GitHub repo at a pinned commit.
# Usage: vendor-skill.sh <owner/repo> <40-char-sha> <path/in/repo> [name]
# Copies into skills/<name> and appends a row to skills/SOURCES.md.
# It never runs code from the cloned repo. Review the listed files before use.
set -euo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)

die() { printf 'vendor-skill: %s\n' "$*" >&2; exit 1; }

# Keep attribution: if the skill folder has no LICENSE, copy the repo's.
copy_license() {
  local src="$1" dest="$2" f
  ls "$dest"/LICENSE* >/dev/null 2>&1 && return 0
  for f in "$src"/LICENSE "$src"/LICENSE.md "$src"/LICENSE.txt; do
    [ -f "$f" ] && { cp "$f" "$dest/"; return 0; }
  done
  printf 'warning: no LICENSE found in %s\n' "$1" >&2
}

main() {
  [ $# -ge 3 ] || die "usage: $0 <owner/repo> <sha> <path/in/repo> [name]"
  local src="$1" sha="$2" path="${3%/}" name="${4:-$(basename "${3%/}")}"
  local dest="$REPO/skills/$name"
  printf '%s' "$sha" | grep -Eq '^[0-9a-f]{40}$' || die "sha must be a full 40-char commit"
  [ ! -e "$dest" ] || die "$dest already exists; remove it first to re-vendor"

  TMP=$(mktemp -d)
  trap 'rm -rf "$TMP"' EXIT
  git -C "$TMP" init -q
  git -C "$TMP" fetch -q --depth 1 "https://github.com/$src.git" "$sha"
  git -C "$TMP" -c advice.detachedHead=false checkout -q FETCH_HEAD
  [ -f "$TMP/$path/SKILL.md" ] || die "$path/SKILL.md not found at $sha"

  cp -R "$TMP/$path" "$dest"
  copy_license "$TMP" "$dest"
  # shellcheck disable=SC2016  # literal markdown backticks
  printf '| %s | [%s](https://github.com/%s/tree/%s/%s) | `%s` | %s | TODO: review |\n' \
    "$name" "$src" "$src" "$sha" "$path" "${sha:0:12}" "$(date +%Y-%m-%d)" >>"$REPO/skills/SOURCES.md"

  printf 'vendored %s -> %s\nNon-markdown files to review before use:\n' "$src/$path" "$dest"
  (cd "$dest" && find . -type f ! -name '*.md' | sort | sed 's/^/  /')
}

main "$@"
