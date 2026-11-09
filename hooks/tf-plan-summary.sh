#!/usr/bin/env bash
# PostToolUse(Bash): after a terraform/tofu plan (or tf-run.sh ... plan) that destroys or
# replaces anything, tell the agent exactly what, flagging data and identity resources,
# so it reports them to the user before handing over the apply command.
set -u
# shellcheck source=hooks/lib.sh
. "$(dirname "$0")/lib.sh"

PLAN_CMD='(^|[;&|[:space:]/])((terraform|tofu)([[:space:]]+-chdir=[^[:space:]]+)?|tf-run\.sh([[:space:]].*)?)[[:space:]]+plan([[:space:]]|$)'
RISKY='(aws_db_|aws_rds_|aws_s3_bucket|aws_iam_|aws_kms_|aws_secretsmanager_|aws_dynamodb_table)'

main() {
  local cmd out counts changes risky
  read_input
  cmd=$(json_get '.tool_input.command')
  [[ "$cmd" =~ $PLAN_CMD ]] || exit 0
  out=$(printf '%s' "$HOOK_INPUT" | jq -r '[.tool_response.stdout, .tool_response.stderr, .tool_response.output] | map(select(. != null)) | join("\n")' 2>/dev/null |
    sed -E $'s/\x1b\\[[0-9;]*m//g')
  counts=$(printf '%s\n' "$out" | grep -Eo 'Plan: [0-9]+ to add, [0-9]+ to change, [0-9]+ to destroy' | tail -n 1)
  changes=$(printf '%s\n' "$out" | grep -E '^[[:space:]]*# [^[:space:]]+ (must be replaced|will be destroyed)' | sed -E 's/^[[:space:]]*# //')
  [ -n "$changes" ] || exit 0
  risky=$(printf '%s\n' "$changes" | grep -E "(^|\\.)$RISKY")
  block "Terraform plan summary: ${counts:-counts not found}
Destroyed or replaced:
$changes
${risky:+
DATA / IDENTITY RESOURCES AT RISK (summarise these for the user first):
$risky
}
Never apply. Summarise this for the user and hand over the apply command for them to run."
}

main
