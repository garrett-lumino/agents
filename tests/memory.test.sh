#!/usr/bin/env bash
# shellcheck disable=SC2016 # single quotes hold jq filters and child-shell scripts, expanded there
# Shared AI memory: vault link hook, memory lint, vault commit, harness installer.
set -u
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

H="$TMP/home"                       # fake $HOME
V="$H/dev/obsidian"                 # default vault under it
P="$H/.claude/projects"
PRE=$(printf '%s' "$H/dev/github/" | tr '/' '-')

memfile() { # memfile <path> <name> [type]
  printf -- '---\nname: %s\ndescription: d\nmetadata:\n  type: %s\n---\nbody\n' "$2" "${3:-user}" >"$1"
}
jqe() { jq -e "$@" >/dev/null; }
run_link() { printf '%s' "$1" | HOME="$H" "$HOOKS/memory-to-vault.sh"; }

test_lint() {
  local d="$TMP/lint" out
  mkdir -p "$d"
  printf -- '- [A](a.md) — x\n- [Hub](hub.md) — y\n- [Gone](gone.md) — z\n' >"$d/MEMORY.md"
  memfile "$d/a.md" a
  printf -- '---\nname: hub\ndescription: d\nmetadata:\n  type: user\n---\nsee [[child]]\n' >"$d/hub.md"
  memfile "$d/child.md" child
  memfile "$d/orphan.md" "Wrong Name"
  out=$("$HOOKS/memory-lint.sh" "$d")
  check "lint: orphan reported" grep -q 'orphan.md: not reachable' <<<"$out"
  check "lint: name mismatch reported" grep -q 'orphan.md: name "Wrong Name"' <<<"$out"
  check "lint: dangling index line reported" grep -q 'points at missing gone.md' <<<"$out"
  check "lint: hub-linked file not reported" bash -c '! grep -q child.md <<<"$1"' _ "$out"
  check "lint: indexed file not reported" bash -c '! grep -q "lint/a.md" <<<"$1"' _ "$out"
}

test_link_hook() {
  local out
  mkdir -p "$V/claude-memory/existing" "$P/${PRE}moved/memory" "$P/${PRE}existing/memory" "$P/${PRE}fresh" "$P/${PRE}nomem"
  echo a >"$P/${PRE}moved/memory/MEMORY.md"
  echo new >"$P/${PRE}existing/memory/new.md"
  echo old >"$V/claude-memory/existing/MEMORY.md"
  out=$(run_link "$(jq -nc --arg t "$P/${PRE}fresh/s.jsonl" '{source:"startup",transcript_path:$t}')")
  check "link: moved dir is a symlink" test -L "$P/${PRE}moved/memory"
  check "link: moved content in vault" test -f "$V/claude-memory/moved/MEMORY.md"
  check "link: merge keeps vault file" grep -q old "$V/claude-memory/existing/MEMORY.md"
  check "link: merge adds new file" test -f "$V/claude-memory/existing/new.md"
  check "link: current project starts in vault" test -L "$P/${PRE}fresh/memory"
  check "link: project without memory untouched" test ! -e "$P/${PRE}nomem/memory"
  check "link: index note generated" test -f "$V/claude-memory/Claude Memory.md"
  check "link: output carries global index" jqe '.hookSpecificOutput.additionalContext | test("Global memory")' <<<"$out"
  out=$(run_link '{"source":"compact"}')
  check "link: compact asks to save memories" jqe '.hookSpecificOutput.additionalContext | test("just compacted")' <<<"$out"
}

test_vault_commit() {
  local r="$TMP/vault" n
  mkdir -p "$r" && git -C "$r" init -q && echo x >"$r/a.md"
  printf '{}' | AGENTS_VAULT="$r" "$HOOKS/vault-commit.sh"
  n=$(git -C "$r" rev-list --count HEAD 2>/dev/null || echo 0)
  check "commit: dirty vault committed" test "$n" = 1
  printf '{}' | AGENTS_VAULT="$r" "$HOOKS/vault-commit.sh"
  check "commit: clean vault makes no commit" test "$(git -C "$r" rev-list --count HEAD)" = 1
  printf '#!/bin/sh\ntouch "%s/pwned"\n' "$TMP" >"$r/.git/hooks/pre-commit" && chmod +x "$r/.git/hooks/pre-commit"
  git -C "$r" config core.fsmonitor "touch $TMP/pwned-fsmonitor #"
  echo y >"$r/b.md"
  printf '{}' | AGENTS_VAULT="$r" "$HOOKS/vault-commit.sh"
  check "commit: still commits with a planted hook" test "$(git -C "$r" rev-list --count HEAD)" = 2
  check "commit: repo pre-commit hook not run" test ! -e "$TMP/pwned"
  check "commit: repo fsmonitor not run" test ! -e "$TMP/pwned-fsmonitor"
  check "commit: no repo is a no-op" sh -c 'printf "{}" | AGENTS_VAULT=/nonexistent "$1"' _ "$HOOKS/vault-commit.sh"
}

test_installer() {
  local i="$TMP/ihome"
  mkdir -p "$i/.cursor" "$i/.codex" "$i/.config/opencode"
  printf '{"mcpServers":{"keep":{"command":"x"}}}\n' >"$i/.cursor/mcp.json"
  for _ in 1 2; do
    HOME="$i" AGENTS_VAULT="$i/vault" AGENTS_NO_LAUNCHD=1 "$ROOT/scripts/install-memory.sh" >/dev/null 2>&1
  done
  check "install: vault AGENTS.md written" test -f "$i/vault/AGENTS.md"
  check "install: vault is a git repo" test -d "$i/vault/.git"
  check "install: cursor keeps other servers" jqe '.mcpServers.keep and .mcpServers["obsidian-memory"]' "$i/.cursor/mcp.json"
  check "install: vault path substituted" jqe --arg v "$i/vault" '.mcpServers["obsidian-memory"].args[-1] == ($v + "/claude-memory")' "$i/.cursor/mcp.json"
  check "install: opencode server added" jqe '.mcp["obsidian-memory"].type == "local"' "$i/.config/opencode/opencode.jsonc"
  check "install: codex table written once" test "$(grep -c '^\[mcp_servers.obsidian-memory\]' "$i/.codex/config.toml")" = 1
  check "install: codex pointer linked" test -L "$i/.codex/AGENTS.md"
  check "install: absent harness skipped" test ! -e "$i/Library/Application Support/Claude/claude_desktop_config.json"
}

test_lint
test_link_hook
test_vault_commit
test_installer
finish
