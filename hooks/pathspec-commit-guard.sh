#!/usr/bin/env bash
# PreToolUse(Bash): in shared checkouts several sessions share one git index, so a
# commit must name its paths after `--`; a bare commit or `-a` sweeps in a peer's
# staged files. Tunable: AGENTS_PATHSPEC_REPOS (owner/name list).
set -u
# shellcheck source=hooks/lib.sh
. "$(dirname "$0")/lib.sh"

REPOS="${AGENTS_PATHSPEC_REPOS:-Lumino-Devs/lumino-services}"

main() {
  local cmd seg root
  read_input
  cmd=$(json_get '.tool_input.command')
  is_commit "$cmd" || exit 0
  root=$(commit_root "$cmd" "$(hook_cwd)") ||
    block "BLOCKED by pathspec-commit-guard: can't tell which repo this commit runs in (cd/--git-dir/GIT_DIR/wrapper). Run the commit from the repo directory."
  in_list "$(origin_repo "$root")" "$REPOS" || exit 0
  # shellcheck disable=SC2020  # per-char on purpose: ; & | each end a segment
  while IFS= read -r seg; do
    is_commit "$seg" || continue
    [[ " $seg " =~ [[:space:]]--[[:space:]]+[^[:space:]\<] ]] && continue
    block "BLOCKED by pathspec-commit-guard: this checkout is shared, so a commit must name its paths after \`--\`.
  command: $seg
Use: git add -- <paths> && git commit -F <msg> -- <paths>"
  done < <(printf '%s\n' "$cmd" | tr ';&|' '\n\n\n')
  exit 0
}

main
