#!/bin/sh
# Print problems in Claude memory folders, one per line, at most 10.
# Usage: memory-lint.sh <memory-dir>...
# Checks: files nothing reaches (not in MEMORY.md, no [[link]] from another memory), index lines pointing at missing files,
# missing name/description/metadata.type, and a name that differs from the filename.
lint_dir() {
  dir=$1 label=$(basename -- "$1") index="$1/MEMORY.md"
  [ -f "$index" ] || { [ -n "$(ls -- "$dir"/*.md 2>/dev/null)" ] && echo "$label: no MEMORY.md index"; return; }
  for f in "$dir"/*.md; do
    [ -e "$f" ] || continue
    file=$(basename -- "$f")
    [ "$file" = MEMORY.md ] && continue
    stem=${file%.md}
    grep -qF "($file)" "$index" ||
      grep -lF -e "[[$stem]]" -e "[[$stem|" -e "($file)" -- "$dir"/*.md 2>/dev/null | grep -qvF "/$file" ||
      echo "$label/$file: not reachable from MEMORY.md (not listed, and no other memory links to it)"
    head=$(awk 'NR==1 && $0!="---"{exit} NR>1 && $0=="---"{exit} NR>1' "$f")
    name=$(printf '%s\n' "$head" | sed -n 's/^name:[[:space:]]*//p' | tr -d '"')
    [ -n "$name" ] || echo "$label/$file: frontmatter has no name"
    [ -z "$name" ] || [ "$name.md" = "$file" ] || echo "$label/$file: name \"$name\" differs from the filename"
    printf '%s\n' "$head" | grep -q '^description:' || echo "$label/$file: frontmatter has no description"
    printf '%s\n' "$head" | grep -qE '^[[:space:]]*type:' || echo "$label/$file: frontmatter has no metadata.type"
  done
  grep -oE '\]\([^)]+\.md\)' "$index" | sed 's/^](//; s/)$//' | while read -r ref; do
    [ -e "$dir/$ref" ] || echo "$label/MEMORY.md: points at missing $ref"
  done
}

for d in "$@"; do
  [ -d "$d" ] && lint_dir "$d"
done | head -n 10
