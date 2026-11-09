#!/usr/bin/env bash
# PreToolUse(Bash): before `git commit`, scan what is about to be committed for
# credentials with gitleaks (staged changes, plus files the same command adds).
# Card numbers are pan-scan.sh's job. Without gitleaks: warn and allow.
set -u
# shellcheck source=hooks/lib.sh
. "$(dirname "$0")/lib.sh"

MAX_FILES=500

# scan <gitleaks args...>: redacted findings on stdout; returns 2 when gitleaks itself failed.
# --exit-code 3 keeps findings apart from gitleaks' own errors.
scan() {
  local out rc
  out=$(gitleaks "$@" --exit-code 3 --redact --no-banner --no-color -v 2>&1)
  rc=$?
  [ "$rc" = 0 ] || [ "$rc" = 3 ] || return 2
  printf '%s\n' "$out" | sed -E $'s/\x1b\\[[0-9;]*m//g' | grep -E '^(RuleID|File|Line):' | paste - - - 2>/dev/null
  return 0
}

# candidate_files <root> <with untracked 0|1>: NUL-separated working-tree files a commit could
# take: modified tracked files (-a, pathspecs, -i/-o), plus untracked ones when it runs git add.
candidate_files() {
  git -C "$1" diff -z --name-only 2>/dev/null
  [ "$2" = 1 ] && git -C "$1" ls-files -z --others --exclude-standard 2>/dev/null
  return 0
}

main() {
  local cmd root out more file untracked n=0
  read_input
  cmd=$(json_get '.tool_input.command')
  is_commit "$cmd" || exit 0
  have gitleaks || { printf 'warning: gitleaks not installed; secret scan skipped\n' >&2; exit 0; }
  root=$(commit_root "$cmd" "$(hook_cwd)") ||
    block "BLOCKED by secret-scan-commit: can't tell which repo this commit runs in (cd/--git-dir/GIT_DIR). Run the commit from the repo directory."
  out=$(scan git --staged "$root") || block "BLOCKED by secret-scan-commit: gitleaks failed on the staged changes; check \`gitleaks git --staged $root\`."
  untracked=0
  # Any `add` word (git -C x add, git --no-pager add, ...): untracked files may be included.
  printf '%s' "$cmd" | grep -Eq '(^|[^[:alnum:]_-])add([^[:alnum:]_-]|$)' && untracked=1
  while IFS= read -r -d '' file; do
    n=$((n + 1))
    [ "$n" -le "$MAX_FILES" ] || block "BLOCKED by secret-scan-commit: more than $MAX_FILES changed files to scan; stage what you mean to commit (git add), then commit with -- <paths>."
    [ -f "$root/$file" ] || continue
    more=$(scan dir "$root/$file") || block "BLOCKED by secret-scan-commit: gitleaks failed on $file."
    out="$out$more"
  done < <(candidate_files "$root" "$untracked")
  [ -n "$out" ] || exit 0
  block "BLOCKED by secret-scan-commit: gitleaks found credentials in what this commit would include (values redacted):
$out
Remove the secret (keep it in Doppler / Secrets Manager), or if it is a test fixture, add a .gitleaksignore entry by fingerprint, then commit again."
}

main
