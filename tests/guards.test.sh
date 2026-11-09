#!/usr/bin/env bash
# shellcheck disable=SC2016 # test inputs are single-quoted on purpose: ${...} and `...` must reach the hook unexpanded
# Work guards: secret printing, PII in logs, kubectl prod, terraform plan
# summary, PR naming, pathspec commits, heavy jobs, secret scan on commit.
set -u
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

test_secret_print_guard() {
  local h=secret-print-guard.sh
  bash_case 2 $h 'doppler secrets get STRIPE_KEY --plain'
  bash_case 2 $h 'doppler secrets'
  bash_case 2 $h 'doppler secrets download --no-file --format env'
  bash_case 2 $h 'aws secretsmanager get-secret-value --secret-id prod/db'
  bash_case 2 $h 'aws ssm get-parameter --name /x --with-decryption'
  bash_case 2 $h 'aws ssm get-parameters-by-path --path /x --with-decryption --recursive'
  bash_case 2 $h 'kubectl get secret db -o yaml'
  bash_case 2 $h 'kubectl -n lux get secrets -o=jsonpath={.data}'
  bash_case 2 $h 'kubectl get pods,secrets -o yaml'
  bash_case 2 $h 'kubectl get -n lux secret db -o yaml'
  bash_case 2 $h 'aws ssm get-parameter-history --name /x --with-decryption'
  bash_case 2 $h 'doppler secrets get STRIPE_KEY --only-names'
  bash_case 0 $h 'kubectl get pods -l app=secret-rotator -o yaml'
  bash_case 0 $h 'doppler secrets --only-names'
  bash_case 0 $h 'doppler run -- pnpm dev'
  bash_case 0 $h 'doppler secrets download --format env'          # writes a file, prints nothing
  bash_case 0 $h 'aws secretsmanager list-secrets'
  bash_case 0 $h 'aws ssm get-parameter --name /x'                 # no decryption
  bash_case 0 $h 'kubectl get secrets'
  bash_case 0 $h 'kubectl describe secret db'                      # shows sizes only
}

# work_repo <name> <branch>: a repo whose origin is lumino-services, on <branch>.
work_repo() {
  local r
  r=$(new_repo "$1")
  git -C "$r" remote add origin git@github.com:Lumino-Devs/lumino-services.git
  git -C "$r" checkout -q -b "$2"
  printf '%s' "$r"
}

test_pr_naming_guard() {
  local h=pr-naming-guard.sh good bad other
  good=$(work_repo prgood feat/LN-5540-ci-watch)
  bad=$(work_repo prbad garrett/tweaks)
  other=$(new_repo prother) && git -C "$other" checkout -q -b whatever
  bash_case 0 $h 'gh pr create --base develop --title "LN-5540: CI watcher"' "$good"
  bash_case 0 $h "gh pr create -t 'LN-5540 / LN-5541: two tickets' --body x" "$good"
  bash_case 2 $h 'gh pr create --title "CI watcher"' "$good"              # title without ticket
  bash_case 2 $h 'gh pr create --title "LN-5540: x"' "$bad"               # branch without type/ticket
  bash_case 0 $h 'gh pr create --title "anything"' "$other"               # other repos untouched
  git -C "$good" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "LN-5540: from the commit"
  bash_case 0 $h 'gh pr create --fill' "$good"                            # title comes from the commit
  git -C "$good" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "no ticket here"
  bash_case 2 $h 'gh pr create --fill' "$good"
  bash_case 0 $h 'gh pr view 12' "$good"
}

test_pathspec_commit_guard() {
  local h=pathspec-commit-guard.sh r other
  r=$(work_repo pathspec feat/LN-1-x)
  other=$(new_repo pathother)
  bash_case 2 $h 'git commit -m "LN-1: x"' "$r"
  bash_case 2 $h 'git commit -am "LN-1: x"' "$r"
  bash_case 2 $h 'git commit --amend --no-edit' "$r"
  bash_case 0 $h 'git add -- a.go && git commit -m "LN-1: x" -- a.go' "$r"
  bash_case 0 $h "git commit -F - -- a.go b.go <<'EOF'" "$r"
  bash_case 0 $h 'git commit -m "x"' "$other"                            # other repos untouched
  bash_case 0 $h 'git status' "$r"
}

test_heavy_job_guard() {
  local h=heavy-job-guard.sh pid
  bash_case 0 $h 'pnpm test:lux'                                          # nothing running
  bash -c 'exec -a "pnpm test:lux" sleep 30' &
  pid=$!
  sleep 0.3
  bash_case 2 $h 'docker build -t x .'
  bash_case 2 $h 'pnpm validate:affected'
  bash_case 0 $h 'go test -race -p 2 ./lux/pkg/feed'                      # narrow runs are fine
  bash_case 0 $h 'git status'
  kill "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
  bash_case 0 $h 'docker compose up --build'
}

test_pii_log_guard() {
  local h=pii-log-guard.sh
  write_case 2 $h svc.go 'slog.Info("signup", "email", u.Email)'
  write_case 2 $h svc.go 'log.Printf("login from %s", r.RemoteAddr)'
  write_case 2 $h svc.ts 'this.logger.log(`payload ${JSON.stringify(req.body)}`)'
  write_case 2 $h page.tsx 'console.error("bad phone", user.phoneNumber)'
  write_case 0 $h svc.go 'slog.Info("signup", "user_id", u.ID)'
  write_case 0 $h svc.go 'email := strings.ToLower(in.Email) // not a log call'
  write_case 0 $h svc.go 'slog.Info("hashed", "email_hash", hash(u.Email)) // pii-ok: salted hash, not the address'
  write_case 0 $h tool.py 'logging.info(user.email)'                    # Go/TS only
}

tf_json() { # tf_json <command> <stdout>
  jq -nc --arg c "$1" --arg o "$2" '{tool_name:"Bash",tool_input:{command:$c},tool_response:{stdout:$o,stderr:""}}'
}

test_tf_plan_summary() {
  local h=tf-plan-summary.sh replace adds
  replace='  # aws_db_instance.core must be replaced
-/+ resource "aws_db_instance" "core" {
  # module.web.aws_ecs_service.app will be updated in-place
Plan: 1 to add, 1 to change, 1 to destroy.'
  adds='  # aws_s3_bucket.logs will be created
Plan: 1 to add, 0 to change, 0 to destroy.'
  expect 2 "tf: replace of RDS is called out" $h "$(tf_json 'terraform plan -out p.tfplan' "$replace")"
  expect 2 "tf: tf-run.sh plan too" $h "$(tf_json 'scripts/cicd/tf-run.sh --root lux -- plan' "$replace")"
  expect 0 "tf: adds only stay quiet" $h "$(tf_json 'terraform plan' "$adds")"
  expect 0 "tf: not a plan" $h "$(tf_json 'terraform fmt -check' "$replace")"
  printf '%s' "$(tf_json 'terraform plan' "$replace")" | "$HOOKS/$h" 2>"$TMP/tf-err" >/dev/null
  check "tf: names the resource and the counts" grep -q 'aws_db_instance.core.*replaced' "$TMP/tf-err"
  check "tf: says never apply" grep -qi 'never apply' "$TMP/tf-err"
}

test_secret_scan_commit() {
  local h=secret-scan-commit.sh r
  r=$(new_repo leaks)
  printf 'package x\n' >"$r/clean.go" && git -C "$r" add clean.go
  bash_case 0 $h 'git commit -m "clean"' "$r"
  printf 'aws_access_key_id = AKIAZ7Q3XG4ZKXMPLE42\naws_secret_access_key = wJalrXUtnFEMI/K7MDENG/bPxRfiCYzEXAMPLEKEYx9\n' >"$r/creds.env"
  bash_case 2 $h 'git add -- creds.env && git commit -m x -- creds.env' "$r"   # about to be added
  git -C "$r" add creds.env
  bash_case 2 $h 'git commit -m "x"' "$r"                                        # staged
  bash_case 0 $h 'git status' "$r"
  expect 0 "secret-scan: gitleaks missing warns and allows" $h \
    "$(jq -nc --arg d "$r" '{tool_name:"Bash",cwd:$d,tool_input:{command:"git commit -m x"}}')" "$(jq_only_path)"
}

test_secret_print_guard
test_pii_log_guard
test_tf_plan_summary
test_secret_scan_commit
test_pr_naming_guard
test_pathspec_commit_guard
test_heavy_job_guard
finish
