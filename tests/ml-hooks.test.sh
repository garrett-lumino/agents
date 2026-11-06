#!/usr/bin/env bash
# ML hooks: GPU launch gate, supply-chain guard, write guard, PAN scanner.
set -u
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

estimate() { # estimate <dir> <est_usd> <max_usd> [timeout]
  mkdir -p "$1/.ml"
  jq -nc --argjson e "$2" --argjson m "$3" --arg t "${4:-2h}" \
    '{provider:"hf",flavor:"l4x1",usd_per_hour:0.8,est_hours:2,est_usd:$e,max_usd:$m,timeout:$t}' >"$1/.ml/cost-estimate.json"
}
attest() { mkdir -p "$1/.ml" && jq -nc --argjson h "$2" '{dataset_sha256:"ab12",scanner:"pan-scan",pan_hits:$h}' >"$1/.ml/data-attestation.json"; }

test_launch_gate() {
  local p="$TMP/ml"
  mkdir -p "$p"
  bash_case 2 ml-launch-gate.sh 'hf jobs uv run --flavor l4x1 train.py' "$p"
  bash_case 2 ml-launch-gate.sh 'modal run train.py' "$p"
  bash_case 2 ml-launch-gate.sh 'runpodctl create pod --gpuType "RTX 4090"' "$p"
  expect 2 "launch: MCP hf_jobs without estimate" ml-launch-gate.sh \
    "$(jq -nc --arg d "$p" '{tool_name:"mcp__hf-mcp-server__hf_jobs",cwd:$d,tool_input:{}}')"
  estimate "$p" 3 10
  bash_case 2 ml-launch-gate.sh 'hf jobs uv run train.py' "$p" # no attestation yet
  attest "$p" 0
  bash_case 0 ml-launch-gate.sh 'hf jobs uv run --flavor l4x1 train.py' "$p"
  expect 0 "launch: MCP hf_jobs with estimate" ml-launch-gate.sh \
    "$(jq -nc --arg d "$p" '{tool_name:"mcp__hf-mcp-server__hf_jobs",cwd:$d,tool_input:{}}')"
  estimate "$p" 30 10
  bash_case 2 ml-launch-gate.sh 'hf jobs uv run train.py' "$p" # over budget
  estimate "$p" 3 10 && touch -t 202001010000 "$p/.ml/cost-estimate.json"
  bash_case 2 ml-launch-gate.sh 'hf jobs uv run train.py' "$p" # stale
  estimate "$p" 3 10 && attest "$p" 2
  bash_case 2 ml-launch-gate.sh 'hf upload me/ds data/' "$p" # dirty attestation
  bash_case 0 ml-launch-gate.sh 'hf download Qwen/Qwen3-4B' "$p"
  bash_case 0 ml-launch-gate.sh 'ls -la' "$p"
  expect 2 "launch: jq missing fails closed" ml-launch-gate.sh '{}' "$(no_jq_path)"
  expect 0 "non-gate hook: jq missing warns and allows" supply-chain-guard.sh '{}' "$(no_jq_path)"
}

test_supply_chain_guard() {
  local repo
  bash_case 2 supply-chain-guard.sh 'hf repo create me/model'
  bash_case 0 supply-chain-guard.sh 'hf repo create me/model --private'
  bash_case 2 supply-chain-guard.sh 'pip install git+https://github.com/a/b'
  bash_case 2 supply-chain-guard.sh 'uvx --from git+https://github.com/a/b@main tool'
  bash_case 0 supply-chain-guard.sh 'pip install git+https://github.com/a/b@0123456789abcdef0123456789abcdef01234567'
  bash_case 0 supply-chain-guard.sh 'pip install requests==2.32.3'
  bash_case 2 supply-chain-guard.sh 'python serve.py --trust-remote-code'
  repo=$(new_repo sc)
  printf 'x' >"$repo/model.safetensors" && git -C "$repo" add model.safetensors
  bash_case 2 supply-chain-guard.sh 'git commit -m "add model"' "$repo"
  git -C "$repo" rm -q --cached model.safetensors && rm "$repo/model.safetensors"
  printf 'K=1' >"$repo/.env"
  bash_case 2 supply-chain-guard.sh 'git add -A && git commit -m wip' "$repo"
  rm "$repo/.env" && printf 'K=' >"$repo/.env.example" && printf 'package x\n' >"$repo/x.go"
  bash_case 0 supply-chain-guard.sh 'git add -A && git commit -m "add x"' "$repo"
}

test_guard_write() {
  write_case 2 guard-write.sh train.py 'model = AutoModel.from_pretrained(name, trust_remote_code=True)'
  write_case 0 guard-write.sh train.py 'model = AutoModel.from_pretrained(name)'
  write_case 0 guard-write.sh notes.md 'never set trust_remote_code=True'
  write_case 2 guard-write.sh data/x.jsonl '{"text":"card 4111 1111 1111 1111"}'
  write_case 0 guard-write.sh data/x.jsonl '{"text":"card 1234 5678 9012 3456"}'
  write_case 0 guard-write.sh data/x.jsonl '{"text":"order 4111111111111112"}'
  write_case 0 guard-write.sh internal/pay/card_test.go 'pan := "4111111111111111"'
}

pan_reported_masked() {
  local got
  printf 'a 5555-5555-5555-4444 b\n' >"$TMP/pans.txt"
  got=$("$HOOKS/pan-scan.sh" "$TMP/pans.txt")
  [ $? -eq 1 ] || return 1
  printf '%s' "$got" | grep -q '555555\*\*\*\*\*\*4444' && ! printf '%s' "$got" | grep -q '5555-5555'
}
long_id_ignored() { printf 'id 12345678901234567890123\n' | "$HOOKS/pan-scan.sh" >/dev/null; }

test_pan_scan() {
  check "pan-scan masks and reports a Mastercard test PAN" pan_reported_masked
  check "pan-scan ignores 23-digit ids" long_id_ignored
}

test_launch_gate
test_supply_chain_guard
test_guard_write
test_pan_scan
finish
