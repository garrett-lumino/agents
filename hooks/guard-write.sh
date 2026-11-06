#!/usr/bin/env bash
# PostToolUse(Edit|Write): no trust_remote_code in code/config, and no card
# numbers in data or eval files.
set -u
# shellcheck source=hooks/lib.sh
. "$(dirname "$0")/lib.sh"

CODE_OR_CONFIG='\.(py|ipynb|ya?ml|toml|json|cfg|sh)$'
DATA_FILE='(^|/)(data|evals?)/|\.(jsonl|csv)$'
REMOTE_CODE='trust_remote_code[[:space:]]*[=:][[:space:]]*(True|true)|--trust-remote-code'

main() {
  local file text hits
  read_input
  file=$(json_get '.tool_input.file_path')
  [ -n "$file" ] || exit 0
  text=$(edited_text)
  if printf '%s' "$file" | grep -Eq "$CODE_OR_CONFIG" && printf '%s' "$text" | grep -Eq "$REMOTE_CODE"; then
    block "trust_remote_code enabled in $file. It runs arbitrary code from the model repo; use a model that loads without it."
  fi
  printf '%s' "$file" | grep -Eq "$DATA_FILE" || exit 0
  hits=$(printf '%s\n' "$text" | "$(dirname "$0")/pan-scan.sh") && exit 0
  block "Possible card numbers written to $file:
$hits
Remove or tokenise them (see training-data-hygiene). Real PANs must never reach training or eval data."
}

main
