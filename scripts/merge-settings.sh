#!/usr/bin/env bash
# Merge claude/settings.json into ~/.claude/settings.json, leaving other keys alone.
# Hook groups whose command lives under /agents/hooks/ are owned by this repo:
# they are replaced on every run, so re-running never duplicates them.
set -euo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)
SRC="$REPO/claude/settings.json"
DST="$HOME/.claude/settings.json"

# shellcheck disable=SC2016  # jq program, not shell
MERGE='
  .[0] as $cur | .[1] as $add
  | def ours: any(.hooks[]?.command // ""; contains("/agents/hooks/"));
  $cur
  | .enabledPlugins = (($cur.enabledPlugins // {}) + $add.enabledPlugins)
  | .extraKnownMarketplaces = (($cur.extraKnownMarketplaces // {}) + $add.extraKnownMarketplaces)
  | .hooks = reduce ($add.hooks | to_entries[]) as $e (($cur.hooks // {});
      .[$e.key] = (((.[$e.key] // []) | map(select(ours | not))) + $e.value))
'

main() {
  [ -f "$DST" ] || printf '{}\n' >"$DST"
  TMP=$(mktemp)
  trap 'rm -f "$TMP"' EXIT
  jq -s "$MERGE" "$DST" "$SRC" >"$TMP"
  jq -e . "$TMP" >/dev/null
  if cmp -s <(jq -S . "$DST") <(jq -S . "$TMP"); then
    printf 'settings: already up to date\n'
    return 0
  fi
  cat "$TMP" >"$DST"
  printf 'settings: merged %s into %s\n' "$SRC" "$DST"
}

main "$@"
