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
  git -C "$repo" checkout -q -b develop
  blocked 'git reset --hard origin/develop' "$repo"
  git -C "$repo" checkout -q -b feature
  allowed 'git reset --hard HEAD~1' "$repo"
}

test_guard_protected_push() {
  local repo
  repo=$(new_repo push)
  blocked 'git push' "$repo"                     # on main
  blocked 'git push origin main' "$repo"
  blocked 'git push origin HEAD' "$repo"         # HEAD is main
  allowed 'git push origin --tags' "$repo"
  git -C "$repo" checkout -q -b feat/ln-1-x
  allowed 'git push -u origin feat/ln-1-x' "$repo"
  allowed 'git push' "$repo"
  allowed 'git push origin HEAD' "$repo"
  blocked 'git push origin feat/ln-1-x:develop' "$repo"
  blocked 'git push origin HEAD:refs/heads/master' "$repo"
}

# The agents repo itself may take direct pushes to main; nothing else may.
test_guard_direct_push_repo() {
  local own other
  local work=https://github.com/Lumino-Devs/lumino-services.git
  own=$(new_repo own) && git -C "$own" remote add origin git@github.com:garrett-lumino/agents.git
  git -C "$own" config branch.main.remote origin
  git -C "$own" remote add work "$work"
  other=$(new_repo other) && git -C "$other" remote add origin "$work"
  allowed 'git push origin main' "$own"
  allowed 'git push' "$own"                          # upstream remote is origin
  allowed "git -C $own push origin main" "$other"   # -C names the repo, not the cwd
  blocked 'git push origin main' "$other"
  blocked "git -C $other push origin main" "$own"
  # The exemption follows where the push really goes, and fails closed otherwise.
  blocked 'git push work main' "$own"                                     # another remote
  blocked "git push $work HEAD:develop" "$own"                            # a raw URL
  blocked "cd $other && git push origin main" "$own"                       # cd moves the repo
  blocked "pushd $other; git push origin main" "$own"
  blocked "git --git-dir=$other/.git push origin main" "$own"
  blocked "GIT_DIR=$other/.git git push origin main" "$own"
  blocked "git -C $own -C $other push origin main" "$other"                # -C stacks
  blocked "git -c remote.origin.pushurl=$work push origin main" "$own"     # config override
  blocked 'git push --repo=work main' "$own"
  # Only a single plain `git [-C dir] push [flags] [remote [refspec...]]` is exempt.
  allowed 'git push -u origin main' "$own"
  blocked "\"c\"d $other && git push origin main" "$own"                     # quoted cd
  blocked "git remote set-url --push origin $work && git push origin main" "$own"
  blocked 'git push --receive-pack git-receive-pack origin main' "$own"      # option value read as remote
  blocked 'git push --exec /tmp/x origin main' "$own"
  blocked 'HOME=/tmp/x git push origin main' "$own"                          # env prefix
  blocked 'env GIT_DIR=x git push origin main' "$own"
  blocked 'git push origin +HEAD:main' "$own"                                # forced refspec
  blocked 'git push origin main 2>&1' "$own"                                 # anything extra
  git -C "$own" remote set-url --push origin "$work"
  blocked 'git push origin main' "$own"                                    # push URL differs from fetch
  git -C "$own" config --unset remote.origin.pushurl
  git -C "$own" config url.https://github.com/Lumino-Devs/.pushInsteadOf git@github.com:garrett-lumino/
  blocked 'git push origin main' "$own"                                    # pushInsteadOf rewrite
  git -C "$own" config --unset url.https://github.com/Lumino-Devs/.pushInsteadOf
  allowed 'git push origin main' "$own"
  git -C "$own" remote set-url origin https://github.com.evil.example/garrett-lumino/agents.git
  blocked 'git push origin main' "$own"                                    # wrong host
}

sql_tool_json() { jq -nc --arg q "$1" '{tool_name:"mcp__claude_ai_Supabase__execute_sql",tool_input:{project_id:"p",query:$q}}'; }

test_guard_sql_mcp() {
  expect 2 "mcp sql: DROP TABLE" guard-bash.sh "$(sql_tool_json 'DROP TABLE merchants;')"
  expect 2 "mcp sql: DELETE FROM" guard-bash.sh "$(sql_tool_json 'delete from ledger_entries where id = 1')"
  expect 0 "mcp sql: SELECT" guard-bash.sh "$(sql_tool_json 'select id from merchants limit 5')"
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

# Stub formatters that record they ran; proves opt-in behaviour without real tools.
stub_formatters() {
  local bin="$TMP/stubs" t
  mkdir -p "$bin"
  for t in gofumpt ruff; do
    printf '#!/bin/sh\ntouch "%s/ran-%s"\n' "$TMP" "$t" >"$bin/$t" && chmod +x "$bin/$t"
  done
  ln -sf "$(command -v jq)" "$bin/jq"
  printf '%s' "$bin:/usr/bin:/bin"
}

ran() { [ -e "$TMP/ran-$1" ]; }

test_format_opt_in() {
  local path p="$TMP/optin"
  path=$(stub_formatters)
  mkdir -p "$p/go" "$p/py"
  printf 'package x\n' >"$p/go/x.go" && printf 'x = 1\n' >"$p/py/x.py"
  expect 0 "format: go edit, no golangci config" format-on-edit.sh "$(edit_json "$p/go/x.go")" "$path"
  check "format: gofumpt skipped without opt-in" eval '! ran gofumpt'
  printf 'formatters:\n  enable: [gofumpt]\n' >"$p/go/.golangci.yml"
  expect 0 "format: go edit, gofumpt enabled" format-on-edit.sh "$(edit_json "$p/go/x.go")" "$path"
  check "format: gofumpt runs when .golangci.yml enables it" ran gofumpt
  expect 0 "format: py edit, no ruff config" format-on-edit.sh "$(edit_json "$p/py/x.py")" "$path"
  check "format: ruff skipped without opt-in" eval '! ran ruff'
  printf '[tool.ruff]\nline-length = 100\n' >"$p/py/pyproject.toml"
  expect 0 "format: py edit, ruff configured" format-on-edit.sh "$(edit_json "$p/py/x.py")" "$path"
  check "format: ruff runs when pyproject has [tool.ruff]" ran ruff
}

test_guard_rm
test_guard_sql
test_guard_terraform_git
test_guard_reset
test_guard_protected_push
test_guard_direct_push_repo
test_guard_sql_mcp
test_guard_aws
test_stop_gate
test_format_on_edit
test_format_opt_in
finish
