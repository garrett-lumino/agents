#!/usr/bin/env bash
# PostToolUse(Edit|Write|MultiEdit): format the edited file, lint only that file/package.
set -u
# shellcheck source=hooks/lib.sh
. "$(dirname "$0")/lib.sh"

# find_up <start-dir> <name>... -> first directory (walking up) containing any name.
find_up() {
  local dir="$1" name
  shift
  while :; do
    for name in "$@"; do
      [ -e "$dir/$name" ] && { printf '%s' "$dir"; return 0; }
    done
    [ "$dir" = / ] && return 1
    dir=$(dirname "$dir")
  done
}

# Prefer the project's node_modules/.bin, then a global install.
node_bin() {
  local root="$1" name="$2"
  if [ -x "$root/node_modules/.bin/$name" ]; then
    printf '%s' "$root/node_modules/.bin/$name"
  elif have "$name"; then
    command -v "$name"
  else
    return 1
  fi
}

lint_failed() { block "Lint failed for $1 - fix before continuing:
$(printf '%s\n' "$2" | tail -n 60)"; }

format_go() {
  local file="$1" dir out rev=()
  have goimports && goimports -w "$file" >/dev/null 2>&1
  have gofumpt && gofumpt -w "$file" >/dev/null 2>&1
  have golangci-lint || return 0
  dir=$(dirname "$file")
  find_up "$dir" .golangci.yml .golangci.yaml .golangci.toml .golangci.json >/dev/null || return 0
  git -C "$dir" rev-parse --verify -q HEAD >/dev/null 2>&1 && rev=(--new-from-rev=HEAD)
  out=$(cd "$dir" && golangci-lint run "${rev[@]}" --timeout=60s . 2>&1) && return 0
  toolchain_broken "$out" && return 0
  lint_failed "$file" "$out"
}

# golangci-lint built with an older Go than the one on PATH can't load the
# stdlib; that's an environment problem, not a finding, so warn and allow.
toolchain_broken() {
  printf '%s' "$1" | grep -Eq "could not import (fmt|errors|internal/)|can't load config|used to build golangci-lint is lower" || return 1
  printf 'warning: golangci-lint cannot load packages (Go toolchain mismatch); rebuild it with the Go on PATH. Lint skipped.\n' >&2
}

format_js() {
  local file="$1" root bin out
  root=$(find_up "$(dirname "$file")" package.json) || root=$(dirname "$file")
  if bin=$(node_bin "$root" prettier) &&
    { [ -x "$root/node_modules/.bin/prettier" ] || find_up "$root" .prettierrc .prettierrc.json .prettierrc.js .prettierrc.cjs .prettierrc.mjs .prettierrc.yaml .prettierrc.yml prettier.config.js prettier.config.mjs prettier.config.cjs >/dev/null; }; then
    "$bin" --write --log-level=warn "$file" >/dev/null 2>&1
  fi
  find_up "$(dirname "$file")" eslint.config.js eslint.config.mjs eslint.config.cjs eslint.config.ts eslint.config.mts .eslintrc .eslintrc.js .eslintrc.cjs .eslintrc.json .eslintrc.yml .eslintrc.yaml >/dev/null || return 0
  bin=$(node_bin "$root" eslint) || return 0
  out=$(cd "$root" && "$bin" --max-warnings=0 "$file" 2>&1) || lint_failed "$file" "$out"
}

format_py() {
  local file="$1" out
  have ruff || return 0
  ruff format -q "$file" >/dev/null 2>&1
  out=$(ruff check --fix -q "$file" 2>&1) || lint_failed "$file" "$out"
}

format_tf() {
  have terraform && terraform fmt "$1" >/dev/null 2>&1
  return 0
}

main() {
  local file
  read_input
  file=$(json_get '.tool_input.file_path')
  [ -n "$file" ] && [ -f "$file" ] || exit 0
  case "$file" in
    *.go) format_go "$file" ;;
    *.ts | *.tsx | *.js | *.jsx | *.mjs | *.cjs) format_js "$file" ;;
    *.py) format_py "$file" ;;
    *.tf | *.tfvars) format_tf "$file" ;;
  esac
  exit 0
}

main
