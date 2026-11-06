#!/usr/bin/env bash
# PostToolUse(Edit|Write): lint suppressions must name the rule and say why.
#   Go:     //nolint:funlen // table-driven dispatch, splitting hurts readability
#   Python: # noqa: E501  # long URL
#   JS/TS:  // eslint-disable-next-line no-console -- CLI entrypoint
set -u
# shellcheck source=hooks/lib.sh
. "$(dirname "$0")/lib.sh"

unexplained() {
  local text="$1"
  printf '%s\n' "$text" | grep -E '//[[:space:]]*nolint' | grep -Ev '//[[:space:]]*nolint[^/]*//[[:space:]]*[^[:space:]]'
  printf '%s\n' "$text" | grep -E '#[[:space:]]*noqa' | grep -Ev 'noqa[^#]*#[[:space:]]*[^[:space:]]'
  printf '%s\n' "$text" | grep -E 'eslint-disable' | grep -Ev 'eslint-disable.*[[:space:]]--[[:space:]]+[^[:space:]]'
}

main() {
  local file hits
  read_input
  file=$(json_get '.tool_input.file_path')
  case "$file" in *.go | *.py | *.ts | *.tsx | *.js | *.jsx | *.mjs | *.cjs) ;; *) exit 0 ;; esac
  hits=$(unexplained "$(edited_text)")
  [ -n "$hits" ] || exit 0
  block "Lint suppression without a reason in $file:
$hits
Fix the finding instead, or give the specific rule and a reason (//nolint:rule // why, # noqa: CODE  # why, eslint-disable rule -- why)."
}

main
