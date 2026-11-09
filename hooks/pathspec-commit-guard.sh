#!/usr/bin/env bash
# PreToolUse(Bash): in shared checkouts several sessions share one git index, so a
# commit must name its paths after `--`; a bare commit or `-a` sweeps in a peer's
# staged files. Tunable: AGENTS_PATHSPEC_REPOS (owner/name list).
set -u
# shellcheck source=hooks/lib.sh
. "$(dirname "$0")/lib.sh"

REPOS="${AGENTS_PATHSPEC_REPOS:-Lumino-Devs/lumino-services}"

main() {
  local cmd seg
  read_input
  cmd=$(json_get '.tool_input.command')
  is_git_commit "$cmd" || exit 0
  in_list "$(origin_repo "$(hook_cwd)")" "$REPOS" || exit 0
  # shellcheck disable=SC2020  # per-char on purpose: ; & | each end a segment
  while IFS= read -r seg; do
    is_git_commit "$seg" || continue
    [[ " $seg " =~ [[:space:]]--[[:space:]]+[^[:space:]\<] ]] && continue
    block "BLOCKED by pathspec-commit-guard: this checkout is shared, so a commit must name its paths after \`--\`.
  command: $seg
Use: git add -- <paths> && git commit -F <msg> -- <paths>"
  done < <(printf '%s\n' "$cmd" | tr ';&|' '\n\n\n')
  exit 0
}

main
