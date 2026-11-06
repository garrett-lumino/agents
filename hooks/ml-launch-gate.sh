#!/usr/bin/env bash
# PreToolUse(Bash, mcp__*hf_jobs*): paid GPU launches need an approved cost estimate,
# and launches or dataset uploads need a clean data attestation. Fails closed.
#   .ml/cost-estimate.json    {provider, flavor, usd_per_hour, est_hours, est_usd, max_usd, timeout}, < 24h old
#   .ml/data-attestation.json {dataset_sha256, scanner, pan_hits: 0, date}
set -u
# shellcheck source=hooks/lib.sh
. "$(dirname "$0")/lib.sh"

LAUNCH='(^|[;&|[:space:]])((hf|huggingface-cli)[[:space:]]+jobs[[:space:]]+(run|uv)|modal[[:space:]]+(run|deploy)|runpodctl[[:space:]]+create|together[[:space:]]+fine-tuning[[:space:]]+create|sky[[:space:]]+launch)([[:space:]]|$)|curl.*cloud\.(lambdalabs\.com|lambda\.ai).*launch'
UPLOAD='(^|[;&|[:space:]])(hf|huggingface-cli)[[:space:]]+upload([[:space:]]|$)'

cost_gate() {
  local f="$1/.ml/cost-estimate.json"
  [ -f "$f" ] || block "BLOCKED: GPU launch without .ml/cost-estimate.json (see gpu-cost-gate skill). Ask the user to approve a max_usd."
  [ -n "$(find "$f" -mmin -1440 2>/dev/null)" ] || block "BLOCKED: .ml/cost-estimate.json is older than 24h; re-estimate with current prices."
  jq -e '.provider and .flavor and .usd_per_hour and .est_hours and .est_usd and .max_usd and .timeout' "$f" >/dev/null 2>&1 ||
    block "BLOCKED: .ml/cost-estimate.json needs provider, flavor, usd_per_hour, est_hours, est_usd, max_usd, timeout."
  jq -e '.est_usd <= .max_usd' "$f" >/dev/null 2>&1 ||
    block "BLOCKED: estimated cost exceeds the approved max_usd in .ml/cost-estimate.json."
}

attestation_gate() {
  local f="$1/.ml/data-attestation.json"
  jq -e '.dataset_sha256 and .pan_hits == 0' "$f" >/dev/null 2>&1 ||
    block "BLOCKED: no clean .ml/data-attestation.json (dataset_sha256, pan_hits: 0). Run training-data-hygiene first."
}

main() {
  local tool cmd root
  read_input_strict
  tool=$(json_get '.tool_name')
  cmd=$(json_get '.tool_input.command')
  root=$(repo_root "$(hook_cwd)")
  if printf '%s' "$tool" | grep -q 'hf_jobs' || printf '%s' "$cmd" | grep -Eq "$LAUNCH"; then
    cost_gate "$root"
    attestation_gate "$root"
  elif printf '%s' "$cmd" | grep -Eq "$UPLOAD"; then
    attestation_gate "$root"
  fi
  exit 0
}

main
