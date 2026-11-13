#!/bin/sh
# Print problems in Claude memory folders, one per line, at most 10.
# Usage: memory-lint.sh <memory-dir>...
# Walks each folder and its feature/topic subfolders. Checks: files nothing reaches (not listed in the
# MEMORY.md of their folder or an ancestor, no [[link]] from another memory), index lines pointing at
# missing files, missing name/description/metadata.type, and a name that differs from the filename.
TMPD=$(mktemp -d) || exit 0
trap 'rm -rf "$TMPD"' EXIT

lint_dir() {
  root=$(cd "$1" && pwd -P) label=$(basename -- "$1")
  [ -f "$root/MEMORY.md" ] || { [ -n "$(ls -- "$root"/*.md 2>/dev/null)" ] && echo "$label: no MEMORY.md index"; return; }
  find "$root" -name '*.md' ! -path '*/.*' >"$TMPD/files"
  # Every [[link]] target, and every index entry as a path relative to the root.
  tr '\n' '\0' <"$TMPD/files" | xargs -0 grep -hoE '\[\[[^]|#]+' 2>/dev/null | sed 's/^\[\[//; s|.*/||' | sort -u >"$TMPD/links"
  : >"$TMPD/listed"
  grep '/MEMORY\.md$' "$TMPD/files" | while read -r index; do
    idir=$(dirname -- "$index") rel=${idir#"$root"}
    grep -oE '\]\([^)]+\.md\)' "$index" | sed 's/^](//; s/)$//' | while read -r ref; do
      case $ref in http*) continue ;; esac
      if [ -e "$idir/$ref" ]; then
        printf '%s\n' "$(cd "$(dirname -- "$idir/$ref")" && pwd -P)/$(basename -- "$ref")" >>"$TMPD/listed"
      else
        echo "$label${rel}/MEMORY.md: points at missing $ref"
      fi
    done
  done
  while read -r f; do
    file=$(basename -- "$f") stem=${file%.md} at="$label${f#"$root"}"
    [ "$file" = MEMORY.md ] && continue
    grep -qxF "$f" "$TMPD/listed" || grep -qxF "$stem" "$TMPD/links" ||
      echo "$at: not reachable from MEMORY.md (not listed, and no other memory links to it)"
    head=$(awk 'NR==1 && $0!="---"{exit} NR>1 && $0=="---"{exit} NR>1' "$f")
    name=$(printf '%s\n' "$head" | sed -n 's/^name:[[:space:]]*//p' | tr -d '"')
    [ -n "$name" ] || echo "$at: frontmatter has no name"
    [ -z "$name" ] || [ "$name.md" = "$file" ] || echo "$at: name \"$name\" differs from the filename"
    printf '%s\n' "$head" | grep -q '^description:' || echo "$at: frontmatter has no description"
    printf '%s\n' "$head" | grep -qE '^[[:space:]]*type:' || echo "$at: frontmatter has no metadata.type"
  done <"$TMPD/files"
}

for d in "$@"; do
  [ -d "$d" ] && lint_dir "$d"
done | head -n 10
