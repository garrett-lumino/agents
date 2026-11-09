#!/usr/bin/env bash
# PreToolUse(Bash): before `git commit`, scan what is about to be committed for
# credentials with gitleaks (staged changes, plus files the same command adds).
# Card numbers are pan-scan.sh's job. Without gitleaks: warn and allow.
set -u
# shellcheck source=hooks/lib.sh
. "$(dirname "$0")/lib.sh"

MAX_FILES=500

# is_commit <text>: a git commit, with any git global options before `commit`.
is_commit() {
  [[ "$1" =~ (^|[\;\&\|[:space:]])git([[:space:]]+-[^[:space:]]+([[:space:]]+[^-[:space:]][^[:space:]]*)?)*[[:space:]]+commit([[:space:]]|$) ]]
}

# commit_root <cmd> <cwd>: the repo the commit runs in, following `cd <dir>` before it and
# `git -C <dir>`; fails when that can't be read with certainty.
commit_root() {
  local dir="$2" seg d re='git[[:space:]]+-C[[:space:]]+([^[:space:]]+)[[:space:]]+commit'
  [[ "$1" =~ --git-dir|--work-tree|GIT_DIR|GIT_WORK_TREE ]] && return 1
  # shellcheck disable=SC2020  # per-char on purpose: ; & | each end a segment
  while IFS= read -r seg; do
    if [[ "$seg" =~ ^[[:space:]]*(cd|pushd)[[:space:]]+([^[:space:]]+)[[:space:]]*$ ]]; then
      d=${BASH_REMATCH[2]}
    elif [[ "$seg" =~ (^|[[:space:]])(cd|pushd|popd)([[:space:]]|$) ]]; then
      return 1
    elif is_commit "$seg"; then
      if [[ "$seg" =~ $re ]]; then d=${BASH_REMATCH[1]}; else break; fi
    else
      continue
    fi
    [[ "$d" =~ [\"\'\$\`\\*?[{] ]] && return 1
    d="${d/#\~/$HOME}"
    [[ "$d" == /* ]] || d="$dir/$d"
    dir=$d
    is_commit "$seg" && break
  done < <(printf '%s\n' "$1" | tr ';&|' '\n\n\n')
  repo_root "$dir"
}

# scan <gitleaks args...>: redacted findings on stdout; returns 2 when gitleaks itself failed.
scan() {
  local out rc
  out=$(gitleaks "$@" --redact --no-banner --no-color -v 2>&1)
  rc=$?
  [ "$rc" -le 1 ] || return 2
  printf '%s\n' "$out" | sed -E $'s/\x1b\\[[0-9;]*m//g' | grep -E '^(RuleID|File|Line):' | paste - - - 2>/dev/null
  return 0
}

# added_files <root>: NUL-separated files the command's `git add` / `commit -a` would include.
added_files() {
  git -C "$1" diff -z --name-only 2>/dev/null
  git -C "$1" ls-files -z --others --exclude-standard 2>/dev/null
}

main() {
  local cmd root out more file n=0
  read_input
  cmd=$(json_get '.tool_input.command')
  is_commit "$cmd" || exit 0
  have gitleaks || { printf 'warning: gitleaks not installed; secret scan skipped\n' >&2; exit 0; }
  root=$(commit_root "$cmd" "$(hook_cwd)") ||
    block "BLOCKED by secret-scan-commit: can't tell which repo this commit runs in (cd/--git-dir/GIT_DIR). Run the commit from the repo directory."
  out=$(scan git --staged "$root") || block "BLOCKED by secret-scan-commit: gitleaks failed on the staged changes; check \`gitleaks git --staged $root\`."
  if printf '%s' "$cmd" | grep -Eq '(^|[;&|[:space:]])git[[:space:]]+add([[:space:]]|$)|git[[:space:]]+commit[[:space:]]+(.*[[:space:]])?(-[a-zA-Z]*a[a-zA-Z]*|--all)([[:space:]]|$)'; then
    while IFS= read -r -d '' file; do
      n=$((n + 1))
      [ "$n" -le "$MAX_FILES" ] || block "BLOCKED by secret-scan-commit: more than $MAX_FILES files to add; stage them first (git add), then commit, so they are scanned in one pass."
      [ -f "$root/$file" ] || continue
      more=$(scan dir "$root/$file") || block "BLOCKED by secret-scan-commit: gitleaks failed on $file."
      out="$out$more"
    done < <(added_files "$root")
  fi
  [ -n "$out" ] || exit 0
  block "BLOCKED by secret-scan-commit: gitleaks found credentials in what this commit would include (values redacted):
$out
Remove the secret (keep it in Doppler / Secrets Manager), or if it is a test fixture, add a .gitleaksignore entry by fingerprint, then commit again."
}

main
