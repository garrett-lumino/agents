#!/usr/bin/env bash
# PreToolUse(Bash): `gh pr create` in the work repo needs a <type>/<TICKET>-<kebab>
# branch and a title starting with the ticket ID (CONTRIBUTING.md).
# Tunables: AGENTS_PR_NAMING_REPOS (owner/name list), AGENTS_TICKET_RE.
set -u
# shellcheck source=hooks/lib.sh
. "$(dirname "$0")/lib.sh"

REPOS="${AGENTS_PR_NAMING_REPOS:-Lumino-Devs/lumino-services}"
TICKET="${AGENTS_TICKET_RE:-(LN|LDEV)-[0-9]+}"
TYPES='feature|feat|bugfix|fix|hotfix|chore|refactor|docs|spike|test|ci|perf'

# pr_title <cmd> <dir>: the title gh will use (--title/-t, else the HEAD commit for --fill).
pr_title() {
  local re='(--title|-t)(=|[[:space:]]+)("([^"]*)"|'"'"'([^'"'"']*)'"'"'|([^[:space:]]+))'
  if [[ "$1" =~ $re ]]; then
    printf '%s' "${BASH_REMATCH[4]}${BASH_REMATCH[5]}${BASH_REMATCH[6]}"
  elif [[ "$1" =~ [[:space:]](--fill|--fill-first|--fill-verbose|-f)([[:space:]]|$) ]]; then
    git -C "$2" log -1 --format=%s 2>/dev/null
  fi
}

main() {
  local cmd dir branch title re
  read_input
  cmd=$(json_get '.tool_input.command')
  [[ "$cmd" =~ (^|[;&|[:space:]])gh[[:space:]]+pr[[:space:]]+create([[:space:]]|$) ]] || exit 0
  dir=$(hook_cwd)
  in_list "$(origin_repo "$dir")" "$REPOS" || exit 0
  re='(--head|-H)(=|[[:space:]]+)([^[:space:]]+)'
  if [[ "$cmd" =~ $re ]]; then branch=${BASH_REMATCH[3]}; else branch=$(git -C "$dir" symbolic-ref --short HEAD 2>/dev/null); fi
  title=$(pr_title "$cmd" "$dir")
  shopt -s nocasematch
  [[ "$branch" =~ ^($TYPES)/$TICKET-[a-z0-9] ]] ||
    block "BLOCKED by pr-naming-guard: branch '$branch' is not <type>/<TICKET>-<short-kebab> (types: ${TYPES//|/, }; e.g. feat/LN-1234-short-description). Rename it (git branch -m) and push again."
  [[ "$title" =~ ^$TICKET ]] ||
    block "BLOCKED by pr-naming-guard: the PR title must start with the ticket ID (e.g. --title \"LN-1234: short description\"); got: '${title:-<none; pass --title>}'"
  exit 0
}

main
