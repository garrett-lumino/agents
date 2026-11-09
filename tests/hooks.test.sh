#!/usr/bin/env bash
# shellcheck disable=SC2016 # test commands are single-quoted on purpose: $(...), `...` and $VARS must reach the hook unexpanded
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
  blocked '(rm -rf ~)'                      # subshell: ) ends the segment
  blocked 'echo $(rm -rf ~)'
  blocked '{ rm -rf ~; }'                   # brace group
  blocked 'rm -rf ${HOME}'                  # ${...} is not a brace group
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
  blocked '(terraform destroy)'
  blocked '{ terraform apply; }'
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
  # Pushes that can overwrite or delete protected branches whatever the current branch.
  blocked 'git push --mirror origin' "$repo"
  blocked 'git push --prune origin' "$repo"
  blocked 'git push --all origin' "$repo"
  blocked 'git push origin :develop' "$repo"
  blocked 'git push origin --delete main' "$repo"
  # Destinations are read the way git reads them, and anything unreadable is refused.
  blocked 'git push origin HEAD:heads/main' "$repo"            # git expands to refs/heads/main
  blocked "git push origin 'HEAD:main'" "$repo"                 # quoted
  blocked 'git push origin "HEAD:develop"' "$repo"
  blocked 'git push origin refs/heads/*:refs/heads/*' "$repo"   # wildcard
  blocked 'git push origin :' "$repo"                           # all matching branches
  # Options: only a known list, spelled out; git accepts abbreviations of the rest.
  blocked 'git push --mirr origin' "$repo"
  blocked 'git push --al origin' "$repo"
  blocked 'git -c remote.origin.mirror=true push origin' "$repo"
  git -C "$repo" config remote.origin.push refs/heads/feat/ln-1-x:refs/heads/main
  blocked 'git push origin' "$repo"                             # configured push refspec
  git -C "$repo" config --unset remote.origin.push
  blocked 'git config remote.origin.push refs/heads/feat/ln-1-x:refs/heads/main; git push origin' "$repo"
  blocked 'git remote set-url --push origin x && git push origin feat/ln-1-x' "$repo"
  blocked 'GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=remote.origin.mirror GIT_CONFIG_VALUE_0=true git push origin' "$repo"
  blocked 'export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=remote.origin.mirror GIT_CONFIG_VALUE_0=true; git push origin' "$repo"
  blocked 'set -a; . ./gitenv; git push origin feat/ln-1-x' "$repo"
  blocked 'git --no-pager config remote.origin.mirror true && git push origin' "$repo"
  allowed 'git push origin feat/ln-1-x 2>&1 | tail -5' "$repo"
  # Heredoc bodies are data, not commands, unless a shell reads them.
  allowed "$(printf 'git commit -F - -- a <<'"'"'EOF'"'"'\nfix: stop the git push origin main in CI; cd tools first\nEOF')" "$repo"
  blocked "$(printf 'bash <<'"'"'EOF'"'"'\ngit push origin main\nEOF')" "$repo"
  blocked "$(printf 'ssh host sh <<EOF\ngit push origin main\nEOF')" "$repo"
  blocked "$(printf 'psql <<EOF\nDROP TABLE users;\nEOF')"                          # SQL still read in heredocs
  # Only a commit message or PR body heredoc is data; every other body is read.
  blocked "$(printf 'cat <<EOF | bash\ngit push origin main\nEOF')" "$repo"
  blocked "$(printf 'git commit -F - <<EOF && bash\ngit push origin main\nEOF')" "$repo"   # something after the marker
  blocked "$(printf 'bash <<X; git commit -F - <<EOF\ngit push origin main\nX\nmsg\nEOF')" "$repo"   # two heredocs
  blocked "$(printf 'cat <<OUTER | bash\ngit commit -F - <<EOF\nx\nEOF\ngit push origin main\nOUTER')" "$repo"  # nested
  blocked "$(printf 'git commit -F - -- a <<EOF\nmsg\nEOF\ngit push origin main')" "$repo"   # commands after the body
  blocked "$(printf 'git commit -F - -- a <<EOF\n$(git push origin main)\nEOF')" "$repo"     # unquoted: the body expands
  blocked 'echo $(git push origin main)' "$repo"                                         # command substitution
  blocked 'echo `git push origin main`' "$repo"
  blocked '(git push origin main)' "$repo"                                               # subshell
  allowed "$(printf 'git add -- a && git commit -F - -- a <<'"'"'EOF'"'"'\nnote: git push origin main later\nEOF')" "$repo"
  allowed "$(printf 'gh pr create --title \"LN-1: x\" --body-file - <<'"'"'EOF'"'"'\nthen git push origin main\nEOF')" "$repo"
  # A push is its own command: commit hooks and fetch/log/diff options can run code.
  blocked 'git add -- a && git commit -m x -- a && git push origin feat/ln-1-x' "$repo"
  blocked "git fetch --upload-pack='touch x' origin && git push origin feat/ln-1-x" "$repo"
  # A push runs alone or after plain git add/commit/status; anything else in the command is refused.
  blocked "cd $TMP && git push origin feat/ln-1-x" "$repo"
  blocked 'HOME=/tmp/x true; git push origin feat/ln-1-x' "$repo"
  blocked 'unset GIT_DIR; git push origin feat/ln-1-x' "$repo"
  blocked "eval 'git config remote.origin.mirror true'; git push origin" "$repo"
  blocked "g'i't conf'ig' remote.origin.mirror true; git push origin" "$repo"
  blocked 'git add $(git config remote.origin.mirror true) && git push origin feat/ln-1-x' "$repo"
  blocked 'git add `x` && git push origin feat/ln-1-x' "$repo"
  blocked 'git diff --output=.git/config && git push origin feat/ln-1-x' "$repo"
  blocked 'git log > .git/config; git push origin feat/ln-1-x' "$repo"  blocked 'env GIT_DIR=x git push origin feat/ln-1-x' "$repo"
  git -C "$repo" checkout -q main
  blocked 'git push origin @' "$repo"                           # @ is HEAD
  allowed 'git push origin @:refs/heads/feat/x' "$repo"         # explicit, unprotected destination
  git -C "$repo" checkout -q feat/ln-1-x
  blocked 'git push origin main' "$repo"                        # no-colon source names its own destination
  allowed 'git push origin --delete feat/old' "$repo"
  allowed 'git push --no-verify -u origin HEAD:feat/ln-1-x' "$repo"
  allowed 'git push origin v1.2.3' "$repo"
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
  blocked 'git push origin --mirror' "$own"                                  # options after the remote
  blocked 'git push origin -d main' "$own"
  blocked 'git push origin --delete main' "$own"
  blocked 'git push origin :main' "$own"                                     # empty source = delete
  blocked 'git push --all' "$own"
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

# kubeconfig <file> <current>: contexts dev-lux, lumino-prod and prod-lux, each on its own cluster.
kubeconfig() {
  printf 'apiVersion: v1\ncontexts:\n' >"$1"
  local c
  for c in dev-lux lumino-prod prod-lux; do printf -- '- context:\n    cluster: %s\n    user: me\n  name: %s\n' "$c" "$c" >>"$1"; done
  printf 'current-context: %s\n' "$2" >>"$1"
}

test_guard_kubectl_prod() {
  local kc="$TMP/kubeconfig"
  kubeconfig "$kc" lumino-prod
  KUBECONFIG="$kc" bash_case 2 guard-bash.sh 'kubectl -n lux rollout restart deploy/play'
  KUBECONFIG="$kc" bash_case 2 guard-bash.sh 'kubectl delete pod x'
  KUBECONFIG="$kc" bash_case 0 guard-bash.sh 'kubectl get pods -n lux'
  KUBECONFIG="$kc" bash_case 0 guard-bash.sh 'kubectl --context dev-lux apply -f x.yaml'
  KUBECONFIG="$kc" bash_case 0 guard-bash.sh 'kubectl logs deploy/play --tail 50'
  kubeconfig "$kc" dev-lux
  KUBECONFIG="$kc" bash_case 0 guard-bash.sh 'kubectl apply -f x.yaml'
  KUBECONFIG="$kc" bash_case 2 guard-bash.sh 'kubectl --context=prod-lux scale deploy/play --replicas 0'
  KUBECONFIG="$kc" bash_case 2 guard-bash.sh 'kubectl exec --context prod-lux -it play -- sh'
  # Read verbs are the allowlist on prod; everything else is refused.
  KUBECONFIG="$kc" bash_case 0 guard-bash.sh 'kubectl --context prod-lux wait --for=condition=ready pod/x'
  KUBECONFIG="$kc" bash_case 0 guard-bash.sh 'kubectl --context prod-lux auth can-i delete pods'
  KUBECONFIG="$kc" bash_case 2 guard-bash.sh 'kubectl --context prod-lux certificate approve csr-1'
  # Prod is also the cluster a context points to, and --cluster/--server/--user values.
  printf 'apiVersion: v1\ncontexts:\n- context:\n    cluster: arn:aws:eks:us-east-1:1:cluster/lumino-prod\n    user: me\n  name: dev-lux\ncurrent-context: dev-lux\n' >"$kc"
  KUBECONFIG="$kc" bash_case 2 guard-bash.sh 'kubectl apply -f x.yaml'
  kubeconfig "$kc" dev-lux
  KUBECONFIG="$kc" bash_case 2 guard-bash.sh 'kubectl --server https://prod.example delete pod x'
  # The verb must be readable: unknown options before it on prod are refused.
  KUBECONFIG="$kc" bash_case 2 guard-bash.sh 'kubectl --context prod-lux --as get delete pod x'
  KUBECONFIG="$kc" bash_case 2 guard-bash.sh 'kubectl --context prod-lux --frobnicate x delete pod x'
  # Switching context or kubeconfig in the same command, or a KUBECONFIG= prefix.
  KUBECONFIG="$kc" bash_case 2 guard-bash.sh 'kubectl config use-context prod-lux && kubectl apply -f x.yaml'
  kubeconfig "$TMP/prodcfg" lumino-prod
  KUBECONFIG="$kc" bash_case 2 guard-bash.sh "KUBECONFIG=$TMP/prodcfg kubectl apply -f x.yaml"
  KUBECONFIG="$kc" bash_case 2 guard-bash.sh "export KUBECONFIG=$TMP/prodcfg; kubectl apply -f x.yaml"
  # Options between auth/config and their subcommand, and option values, can't hide the subcommand.
  KUBECONFIG="$kc" bash_case 2 guard-bash.sh 'kubectl --context prod-lux config -o view set-context prod-lux --namespace x'
  KUBECONFIG="$kc" bash_case 2 guard-bash.sh 'kubectl --context prod-lux auth -v can-i reconcile -f rbac.yaml'
  # Quoted or expanded target values can't be read: writes are refused.
  KUBECONFIG="$kc" bash_case 2 guard-bash.sh "kubectl --context pr''od-lux delete pod x"
  KUBECONFIG="$kc" bash_case 2 guard-bash.sh 'kubectl --context $CTX delete pod x'
  KUBECONFIG="$kc" bash_case 2 guard-bash.sh 'kubectl --context not-in-config apply -f x.yaml'   # unknown context
  # Shell expansion could build the target or the verb: refused for writes.
  KUBECONFIG="$kc" bash_case 2 guard-bash.sh 'kubectl --cont{ext=prod-lux,} delete pod x'
  KUBECONFIG="$kc" bash_case 2 guard-bash.sh 'kubectl $OPTS delete pod x'
  KUBECONFIG="$kc" bash_case 2 guard-bash.sh 'kubectl {delete,} pod x'
  KUBECONFIG="$kc" bash_case 2 guard-bash.sh 'kubectl delete pod x --grace-period --context=dev-lux'   # value swallows the target
  KUBECONFIG="$kc" bash_case 2 guard-bash.sh 'kubectl -shttps://prod.example delete pod x'
  KUBECONFIG="$kc" bash_case 2 guard-bash.sh "kubectl --context dev-lux patch deploy/x -p '{\"spec\":{\"replicas\":1}}'"  # quoted: use a file
  KUBECONFIG="$kc" bash_case 0 guard-bash.sh 'kubectl --context dev-lux patch deploy/x --patch-file p.json'
  KUBECONFIG="$kc" bash_case 2 guard-bash.sh 'kubectl --context=dev-lux delete pod x --cont""ext=prod-lux'   # quote removal
  KUBECONFIG="$kc" bash_case 2 guard-bash.sh 'kubectl delete pod x --context= prod-lux'                      # empty attached value
  KUBECONFIG="$TMP/prodcfg" bash_case 2 guard-bash.sh 'kubectl delete pod x --context= dev-lux'            # empty = current (prod)
  KUBECONFIG="$kc" bash_case 2 guard-bash.sh 'kubectl delete pod x -qs https://prod.example'                # -s in a flag group
  KUBECONFIG="$kc" bash_case 2 guard-bash.sh 'kubectl delete pod x -shttps://prod.example/a=b'              # -s value with an =
  KUBECONFIG="$kc" bash_case 0 guard-bash.sh "kubectl get pods -o jsonpath='{.items[*].metadata.name}'"
  # A context that can't be worked out fails closed for writes only.
  KUBECONFIG="$TMP/missing" bash_case 2 guard-bash.sh 'kubectl apply -f x.yaml'
  KUBECONFIG="$TMP/missing" bash_case 0 guard-bash.sh 'kubectl get pods'
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
test_guard_kubectl_prod
test_guard_sql_mcp
test_guard_aws
test_stop_gate
test_format_on_edit
test_format_opt_in
finish
