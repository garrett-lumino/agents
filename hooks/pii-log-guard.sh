#!/usr/bin/env bash
# PostToolUse(Edit|Write|MultiEdit) on Go/TS: a log call must not carry personal data
# (email, phone, names, IP, request bodies, SSN, DOB). Log an ID or a salted hash.
# A line can opt out with `// pii-ok: <reason>`.
set -u
# shellcheck source=hooks/lib.sh
. "$(dirname "$0")/lib.sh"

LOG_RE='(^|[^[:alnum:]_])(slog|log|logger|console|zap|zerolog)\.|this\.logger\.|\.(Info|Warn|Error|Debug|Fatal)(f|w|ln)?\(|\.(info|warn|error|debug|log|fatal)\('
PII_RE='(^|[^[:alnum:]_])(e_?mail|phone(_?number)?|first_?name|last_?name|full_?name|ip_?address|remote_?addr|ssn|dob|date_?of_?birth)([^[:alnum:]_]|$)|req(uest)?\.(body|ip)|r\.Body'

main() {
  local file hits
  read_input
  file=$(json_get '.tool_input.file_path')
  case "$file" in *.go | *.ts | *.tsx) ;; *) exit 0 ;; esac
  hits=$(edited_text | grep -E "$LOG_RE" | grep -Ei "$PII_RE" | grep -v 'pii-ok:' | head -n 5)
  [ -n "$hits" ] || exit 0
  block "Personal data in a log call in $file:
$hits
Never log email, name, phone, IP, SSN, DOB or whole request bodies. Log an ID or a salted hash instead,
or, if this is not personal data, add \`// pii-ok: <reason>\` on the line."
}

main
