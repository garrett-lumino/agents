#!/usr/bin/env bash
# PreToolUse(Bash): public model repos, unpinned VCS installs, remote code, and
# committing secrets/weights/raw data.
set -u
# shellcheck source=hooks/lib.sh
. "$(dirname "$0")/lib.sh"

FORBIDDEN_FILES='(^|/)\.env(\.[^/]*)?$|\.(safetensors|gguf|bin|pt|pth|ckpt|npz)$|(^|/)adapters/|(^|/)data/raw/'
ALLOWED_ENV='(^|/)\.env\.(example|sample|template)$'

deny() { block "BLOCKED by supply-chain-guard: $1"; }

check_public_repo() {
  printf '%s' "$1" | grep -Eq '(^|[;&|[:space:]])(hf|huggingface-cli)[[:space:]]+repos?[[:space:]]+create([[:space:]]|$)' || return 0
  printf '%s' "$1" | grep -q -- '--private' || deny "'hf repo create' without --private."
}

check_unpinned_vcs() {
  local ref
  printf '%s' "$1" | grep -Eq '(pip|uv|uvx|poetry)[[:space:]].*git\+' || return 0
  while IFS= read -r ref; do
    printf '%s' "$ref" | grep -Eq '@[0-9a-f]{40}([#&].*)?$' || deny "unpinned VCS install '$ref'. Pin it to a full commit: git+URL@<40-char sha>."
  done < <(printf '%s' "$1" | grep -oE "git\+[^[:space:]'\"]+")
}

check_remote_code() {
  printf '%s' "$1" | grep -Eq -- '--trust-remote-code|trust_remote_code[[:space:]]*=[[:space:]]*True' &&
    deny "trust_remote_code runs arbitrary code from the model repo. Pick a model that doesn't need it."
  return 0
}

check_commit_contents() {
  local cmd="$1" root f
  is_git_commit "$cmd" || printf '%s' "$cmd" | grep -Eq '(^|[;&|[:space:]])git[[:space:]]+add([[:space:]]|$)' || return 0
  root=$(repo_root "$(hook_cwd)")
  while IFS= read -r f; do
    printf '%s' "$f" | grep -Eq "$ALLOWED_ENV" && continue
    printf '%s' "$f" | grep -Eq "$FORBIDDEN_FILES" && deny "'$f' would be committed (secrets, weights, adapters, or raw data). Add it to .gitignore."
  done < <(pending_files "$root" "$cmd" | sort -u)
  return 0
}

main() {
  local cmd
  read_input
  cmd=$(json_get '.tool_input.command')
  [ -n "$cmd" ] || exit 0
  check_public_repo "$cmd"
  check_unpinned_vcs "$cmd"
  check_remote_code "$cmd"
  check_commit_contents "$cmd"
  exit 0
}

main
