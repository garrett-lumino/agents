#!/usr/bin/env bash
# PreToolUse(Bash): block commands that print secret values into the transcript,
# where they would be kept in session logs and could reach shared memory.
set -u
# shellcheck source=hooks/lib.sh
. "$(dirname "$0")/lib.sh"

# reason_for <segment>: why the segment prints a secret, or nothing.
reason_for() {
  local s=" $1 "
  if [[ "$s" =~ [[:space:]]doppler[[:space:]]+secrets([[:space:]]|$) ]]; then
    if [[ "$s" =~ [[:space:]]secrets[[:space:]]+download[[:space:]] ]]; then
      [[ "$s" =~ [[:space:]]--no-file[[:space:]] ]] && echo "doppler secrets download --no-file prints every secret"
    elif [[ "$s" =~ [[:space:]]secrets[[:space:]]+get[[:space:]] ]]; then
      echo "doppler secrets get prints secret values"
    elif [[ ! "$s" =~ [[:space:]]--only-names[[:space:]] ]] && [[ ! "$s" =~ [[:space:]]secrets[[:space:]]+(set|delete|upload|substitute|names)[[:space:]] ]]; then
      echo "doppler secrets prints secret values"
    fi
  fi
  [[ "$s" =~ [[:space:]]aws[[:space:]].*secretsmanager[[:space:]]+get-secret-value[[:space:]] ]] &&
    echo "aws secretsmanager get-secret-value prints the secret"
  [[ "$s" =~ [[:space:]]aws[[:space:]].*ssm[[:space:]]+get-parameters?(-by-path|-history)?[[:space:]] ]] &&
    [[ "$s" =~ [[:space:]]--with-decryption[[:space:]] ]] && echo "aws ssm --with-decryption prints SecureString values"
  # `secret`/`secrets` anywhere in the resource list after get: "get pods,secrets", "get -n x secret/db".
  [[ "$s" =~ [[:space:]]kubectl([[:space:]].*)?[[:space:]]get[[:space:]](.*[[:space:],/])?secrets?([[:space:],/.]|$) ]] &&
    [[ "$s" =~ [[:space:]](-o|--output)[[:space:]=]*(yaml|json|jsonpath|go-template) ]] && echo "kubectl get secret -o prints the secret data"
  return 0
}

main() {
  local cmd seg why
  read_input
  cmd=$(json_get '.tool_input.command')
  [ -n "$cmd" ] || exit 0
  # shellcheck disable=SC2020  # per-char on purpose: ; & | each end a segment
  while IFS= read -r seg; do
    why=$(reason_for "$seg")
    [ -n "$why" ] && block "BLOCKED by secret-print-guard: $why.
  command: $seg
Use the value without printing it (e.g. \`doppler run -- <cmd>\`, or pipe it straight into the program that needs it), or ask the user."
  done < <(printf '%s\n' "$cmd" | tr ';&|' '\n\n\n')
  exit 0
}

main
