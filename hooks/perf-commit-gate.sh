#!/usr/bin/env bash
# PreToolUse(Bash): a performance commit must carry benchstat evidence, either in
# the commit message or in a staged perf/*.txt file.
set -u
# shellcheck source=hooks/lib.sh
. "$(dirname "$0")/lib.sh"

PERF_WORDS='(^|[^a-z])(perf(\(|:)|optimi[sz]|faster|speed ?up)'
EVIDENCE='geomean|p=[0-9]'

# Commit message text: the command itself (-m/heredoc) plus any -F file.
message_text() {
  local cmd="$1" root="$2" f
  printf '%s\n' "$cmd"
  f=$(printf '%s' "$cmd" | sed -nE 's/.*(-F|--file)[= ]+([^[:space:]]+).*/\2/p')
  [ -n "$f" ] && [ -f "$root/$f" ] && cat "$root/$f"
  return 0
}

has_perf_file_evidence() {
  local root="$1" cmd="$2" f
  while IFS= read -r f; do
    case "$f" in perf/*.txt) grep -Eq "$EVIDENCE" "$root/$f" 2>/dev/null && return 0 ;; esac
  done < <(pending_files "$root" "$cmd")
  return 1
}

main() {
  local cmd root msg
  read_input
  cmd=$(json_get '.tool_input.command')
  is_git_commit "$cmd" || exit 0
  root=$(repo_root "$(hook_cwd)")
  msg=$(message_text "$cmd" "$root")
  printf '%s' "$msg" | tr '[:upper:]' '[:lower:]' | grep -Eq "$PERF_WORDS" || exit 0
  printf '%s' "$msg" | grep -Eq "$EVIDENCE" && exit 0
  has_perf_file_evidence "$root" "$cmd" && exit 0
  block "BLOCKED: performance commit without benchstat evidence.
Run the baseline and the change with -count=10, then 'benchstat old.txt new.txt',
and paste the table into the commit message or stage it as perf/<topic>.txt (see perf-optimization-loop)."
}

main
