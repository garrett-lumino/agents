#!/usr/bin/env bash
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

test_secret_print_guard
test_pr_naming_guard
test_pathspec_commit_guard
test_heavy_job_guard
finish
