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
  bash_case 0 $h 'doppler secrets --only-names'
  bash_case 0 $h 'doppler run -- pnpm dev'
  bash_case 0 $h 'doppler secrets download --format env'          # writes a file, prints nothing
  bash_case 0 $h 'aws secretsmanager list-secrets'
  bash_case 0 $h 'aws ssm get-parameter --name /x'                 # no decryption
  bash_case 0 $h 'kubectl get secrets'
  bash_case 0 $h 'kubectl describe secret db'                      # shows sizes only
}

test_secret_print_guard
finish
