#!/usr/bin/env bash
# PreToolUse(Bash): before `git commit`, scan what is about to be committed for
# credentials with gitleaks (staged changes, plus files the same command adds).
# Card numbers are pan-scan.sh's job. Without gitleaks: warn and allow.
set -u
# shellcheck source=hooks/lib.sh
. "$(dirname "$0")/lib.sh"

# commit_dir <cmd> <cwd>: the repo the commit runs in (`git -C <dir>` wins).
commit_dir() {
  local re='git[[:space:]]+-C[[:space:]]+([^[:space:]]+)[[:space:]]+commit'
  if [[ "$1" =~ $re ]]; then
    local d="${BASH_REMATCH[1]/#\~/$HOME}"
    [[ "$d" == /* ]] || d="$2/$d"
    printf '%s' "$d"
  else
    printf '%s' "$2"
  fi
}

findings() {
  sed -E $'s/\x1b\\[[0-9;]*m//g' | grep -E '^(RuleID|File|Line):' | paste - - - 2>/dev/null
}

main() {
  local cmd root out file staged
  read_input
  cmd=$(json_get '.tool_input.command')
  is_git_commit "$cmd" || exit 0
  have gitleaks || { printf 'warning: gitleaks not installed; secret scan skipped\n' >&2; exit 0; }
  root=$(repo_root "$(commit_dir "$cmd" "$(hook_cwd)")")
  out=$(gitleaks git --staged --redact --no-banner --no-color -v "$root" 2>/dev/null | findings)
  staged=$(git -C "$root" diff --cached --name-only 2>/dev/null)
  while IFS= read -r file; do
    [ -n "$file" ] && [ -f "$root/$file" ] || continue
    printf '%s\n' "$staged" | grep -Fxq -- "$file" && continue
    out="$out$(gitleaks dir --redact --no-banner --no-color -v "$root/$file" 2>/dev/null | findings)"
  done < <(pending_files "$root" "$cmd" | sort -u | head -n 300)
  [ -n "$out" ] || exit 0
  block "BLOCKED by secret-scan-commit: gitleaks found credentials in what this commit would include (values redacted):
$out
Remove the secret (keep it in Doppler / Secrets Manager), or if it is a test fixture, add a .gitleaksignore entry by fingerprint, then commit again."
}

main
