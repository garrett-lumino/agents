#!/usr/bin/env bash
# Validate every skill in skills/: agentskills.io frontmatter, no auto-run or
# pre-approval, no runtime fetches, size limits for self-written skills.
set -u
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

frontmatter() { awk '/^---[[:space:]]*$/{n++; next} n==1' "$1"; }

# Folded or quoted YAML description -> one line.
description_of() {
  frontmatter "$1" | awk '
    /^description:/ { on=1; sub(/^description:[[:space:]]*[>|-]*[[:space:]]*/, ""); print; next }
    on && /^[[:space:]]/ { print; next }
    { on=0 }' | tr '\n' ' ' | sed -E 's/^[[:space:]"]+|[[:space:]"]+$//g'
}

name_of() { frontmatter "$1" | sed -nE 's/^name:[[:space:]]*["'\'']?([^"'\'']*)["'\'']?[[:space:]]*$/\1/p'; }

# Vendored skills have a row in SOURCES.md; everything else is self-written.
is_own() { ! grep -q "^| $(basename "$(dirname "$1")") |" "$ROOT/skills/SOURCES.md"; }

check_skill() {
  local f="$1" dir name desc
  dir=$(basename "$(dirname "$f")")
  name=$(name_of "$f")
  desc=$(description_of "$f")
  check "$dir: name matches folder ($name)" [ "$name" = "$dir" ]
  check "$dir: name <= 64 chars" [ "${#name}" -le 64 ]
  check "$dir: description present, <= 1024 chars (${#desc})" [ "${#desc}" -gt 0 ] && [ "${#desc}" -le 1024 ]
  check "$dir: no allowed-tools" not_grep '^allowed-tools' <(frontmatter "$f")
  check "$dir: no auto-run ! lines" not_grep '^[[:space:]]*!`' "$f"
  check "$dir: no unpinned (branch) URLs or runtime WebFetch" \
    not_grep 'raw\.githubusercontent\.com/[^ )]*/(main|master|refs/heads)/|Use WebFetch' "$f"
  if is_own "$f"; then
    check "$dir: self-written body <= 150 lines" [ "$(wc -l <"$f")" -le 150 ]
  fi
}

not_grep() { ! grep -Eq "$1" "$2"; }

total_desc_tokens() {
  local f sum=0 d
  for f in "$ROOT"/skills/*/SKILL.md; do
    d=$(description_of "$f")
    sum=$((sum + $(printf '%s' "$d" | wc -w) * 13 / 10))
  done
  printf '%s' "$sum"
}

for f in "$ROOT"/skills/*/SKILL.md; do check_skill "$f"; done
printf 'skills: %d in repo, ~%s always-on description tokens\n' \
  "$(find "$ROOT/skills" -mindepth 2 -maxdepth 2 -name SKILL.md | wc -l | tr -d ' ')" "$(total_desc_tokens)"
finish
