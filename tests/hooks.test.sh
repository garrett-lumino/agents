#!/usr/bin/env bash
# Core hooks: guard-bash, stop-gate, format-on-edit.
set -u
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

blocked() { bash_case 2 guard-bash.sh "$1" "${2:-}"; }
allowed() { bash_case 0 guard-bash.sh "$1" "${2:-}"; }

# shellcheck disable=SC2016  # commands are literal strings fed to the hook
test_guard_rm() {
  blocked 'rm -rf ~'
  blocked 'rm -rf /'
  blocked 'rm -rf "$HOME"'
  blocked 'rm -rf ~/'
  blocked 'sudo rm -fr /usr'
  blocked 'cd x && rm -r -f /Users/someone'
  allowed 'rm -rf ./build'
  allowed 'rm -rf ~/projects/app/node_modules'
  allowed 'ls -la'
}

test_guard_sql() {
  blocked 'psql -c "DROP TABLE users"'
  blocked "echo 'drop table x;' | psql mydb"
  blocked 'psql -c "delete from accounts where id = 1"'
  blocked 'psql -c "TRUNCATE orders"'
  blocked 'sqlite3 db "ALTER TABLE t DROP COLUMN c"'
  allowed 'git branch --delete feature'
  allowed 'truncate -s 0 app.log'
  allowed 'psql -c "select * from users"'
}

test_guard_terraform_git() {
  blocked 'terraform destroy'
  blocked 'terraform -chdir=infra apply -auto-approve'
  allowed 'terraform plan'
  blocked 'git push --force'
  blocked 'git push -f origin feature'
  allowed 'git push origin feature'
}

test_guard_reset() {
  local repo
  repo=$(new_repo reset)
  blocked 'git reset --hard HEAD~1' "$repo"
  git -C "$repo" checkout -q -b feature
  allowed 'git reset --hard HEAD~1' "$repo"
}

test_guard_aws() {
  blocked 'aws s3 rm s3://bucket/key --profile prod'
  blocked 'AWS_PROFILE=prod-admin aws ec2 terminate-instances --instance-ids i-1'
  blocked 'aws --profile Production dynamodb delete-table --table-name t'
  allowed 'aws s3 ls --profile prod'
  allowed 'aws ec2 describe-instances --profile prod'
  allowed 'aws ec2 terminate-instances --instance-ids i-1 --profile dev'
}

stop_json() { jq -nc --arg d "$1" --argjson a "$2" '{cwd:$d,stop_hook_active:$a}'; }

test_stop_gate() {
  mkdir -p "$TMP/nomake" "$TMP/pass" "$TMP/fail" "$TMP/nocheck"
  expect 0 "stop: stop_hook_active=true" stop-gate.sh "$(stop_json "$TMP/fail" true)"
  expect 0 "stop: no Makefile" stop-gate.sh "$(stop_json "$TMP/nomake" false)"
  printf 'check:\n\t@true\n' >"$TMP/pass/Makefile"
  printf 'check:\n\t@echo boom; exit 1\n' >"$TMP/fail/Makefile"
  printf 'build:\n\t@exit 1\n' >"$TMP/nocheck/Makefile"
  expect 0 "stop: make check passes" stop-gate.sh "$(stop_json "$TMP/pass" false)"
  expect 2 "stop: make check fails" stop-gate.sh "$(stop_json "$TMP/fail" false)"
  expect 0 "stop: Makefile without check target" stop-gate.sh "$(stop_json "$TMP/nocheck" false)"
}

test_format_on_edit() {
  printf 'package main\nfunc main(){}\n' >"$TMP/main.go"
  expect 0 "format: .go with gofmt/goimports/golangci-lint missing" format-on-edit.sh \
    "$(edit_json "$TMP/main.go")" "$(jq_only_path)"
  expect 0 "format: missing file" format-on-edit.sh "$(edit_json "$TMP/nope.go")"
  printf 'hello\n' >"$TMP/notes.txt"
  expect 0 "format: unknown extension" format-on-edit.sh "$(edit_json "$TMP/notes.txt")"
  expect 0 "format: no file_path" format-on-edit.sh '{"tool_input":{}}'
}

test_guard_rm
test_guard_sql
test_guard_terraform_git
test_guard_reset
test_guard_aws
test_stop_gate
test_format_on_edit
finish
