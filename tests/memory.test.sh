#!/usr/bin/env bash
# shellcheck disable=SC2016 # single quotes hold jq filters and child-shell scripts, expanded there
# Shared AI memory: vault link hook, memory lint, vault commit, harness installer.
set -u
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

H="$TMP/home"                       # fake $HOME
V="$H/dev/obsidian"                 # default vault under it
P="$H/.claude/projects"

memfile() { # memfile <path> <name> [type]
  printf -- '---\nname: %s\ndescription: d\nmetadata:\n  type: %s\n---\nbody\n' "$2" "${3:-user}" >"$1"
}
jqe() { jq -e "$@" >/dev/null; }
recall() { printf '%s' "$1" | HOME="$H" AGENTS_VAULT="$TMP/rv" "$HOOKS/memory-recall.sh"; }
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
  mkdir -p "$d/feat/deep" "$d/topic"
  printf -- '- [F](feat/f.md) — x\n- [T](topic/MEMORY.md) — y\n- [Lost](feat/lost.md) — z\n' >>"$d/MEMORY.md"
  printf -- '- [T1](t1.md) — x\n- [Up](../a.md) — y\n' >"$d/topic/MEMORY.md"
  memfile "$d/feat/f.md" f
  memfile "$d/feat/deep/stray.md" stray
  memfile "$d/topic/t1.md" t1
  out=$("$HOOKS/memory-lint.sh" "$d")
  check "lint: subfolder file listed in root index not reported" bash -c '! grep -q "feat/f.md" <<<"$1"' _ "$out"
  check "lint: file listed in a nested index not reported" bash -c '! grep -q "t1.md" <<<"$1"' _ "$out"
  check "lint: unlisted subfolder file reported" grep -q 'lint/feat/deep/stray.md: not reachable' <<<"$out"
  check "lint: dangling subfolder link reported" grep -q 'points at missing feat/lost.md' <<<"$out"
}

test_folder_name() {
  local repo wt
  repo=$(new_repo "named-checkout")
  git -C "$repo" remote add origin git@github.com:org/the-repo.git
  check "folder: origin remote names it" test "$("$HOOKS/memory-folder.sh" "$repo")" = the-repo
  wt="$TMP/wt-feature" && git -C "$repo" worktree add -q "$wt" -b feat
  check "folder: worktree shares the repo's folder" test "$("$HOOKS/memory-folder.sh" "$wt")" = the-repo
  repo=$(new_repo "no-remote")
  git -C "$repo" worktree add -q "$TMP/wt-other" -b feat
  check "folder: no remote uses the main checkout's name" test "$("$HOOKS/memory-folder.sh" "$TMP/wt-other")" = no-remote
  mkdir -p "$TMP/plain dir"
  check "folder: non-git dir uses its own name" test "$("$HOOKS/memory-folder.sh" "$TMP/plain dir")" = plain-dir
}

test_link_hook() {
  local out repo wt
  repo=$(cd "$(new_repo "lumino-checkout")" && pwd -P) # git reports resolved paths (/var -> /private/var)
  git -C "$repo" remote add origin https://github.com/org/svc.git
  wt="$TMP/wt-a" && git -C "$repo" worktree add -q "$wt" -b a
  pd() { printf '%s/%s' "$P" "$(printf '%s' "$1" | tr -c 'A-Za-z0-9' '-')"; }
  mkdir -p "$V/claude-memory" "$(pd "$wt")/memory" "$P/untouched/memory"
  echo new >"$(pd "$wt")/memory/new.md"
  echo old >"$P/untouched/memory/keep.md"
  out=$(run_link "$(jq -nc --arg t "$(pd "$wt")/s.jsonl" --arg c "$wt" '{source:"startup",transcript_path:$t,cwd:$c}')")
  check "link: worktree memory moved into the repo folder" test -f "$V/claude-memory/svc/new.md"
  check "link: worktree project dir links the repo folder" test -f "$(pd "$wt")/memory/new.md"
  check "link: main checkout's project dir links it too" test -f "$(pd "$repo")/memory/new.md"
  check "link: no folder named after the worktree" test ! -e "$V/claude-memory/wt-a"
  check "link: other projects untouched" test ! -L "$P/untouched/memory"
  git -C "$repo" remote set-url origin https://github.com/org/renamed.git
  run_link "$(jq -nc --arg t "$(pd "$repo")/s.jsonl" --arg c "$repo" '{transcript_path:$t,cwd:$c}')" >/dev/null
  check "link: stale symlink re-pointed" test "$(readlink "$(pd "$repo")/memory")" = "$V/claude-memory/renamed"
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

# A fake `hermes` that keeps each config key in a file, so the installer's merge is exercised.
fake_hermes() {
  mkdir -p "$TMP/hbin" "$TMP/hcfg"
  cat >"$TMP/hbin/hermes" <<EOF
#!/bin/sh
[ "\$1" = config ] || exit 1
case "\$2" in
  get) [ "\$3" = --json ] || exit 1; cat "$TMP/hcfg/\$4" 2>/dev/null || exit 1 ;;
  set) printf '%s' "\$4" >"$TMP/hcfg/\$3" ;;
esac
EOF
  chmod +x "$TMP/hbin/hermes"
  printf '[{"command":"/other.sh"}]' >"$TMP/hcfg/hooks.pre_llm_call"
}

test_installer() {
  local i="$TMP/ihome"
  fake_hermes
  mkdir -p "$i/.cursor" "$i/.codex" "$i/.config/opencode"
  printf '{"mcpServers":{"keep":{"command":"x"}}}\n' >"$i/.cursor/mcp.json"
  for _ in 1 2; do
    PATH="$TMP/hbin:$PATH" HOME="$i" AGENTS_VAULT="$i/vault" AGENTS_NO_LAUNCHD=1 "$ROOT/scripts/install-memory.sh" >/dev/null 2>&1
  done
  check "install: vault AGENTS.md written" test -f "$i/vault/AGENTS.md"
  check "install: vault is a git repo" test -d "$i/vault/.git"
  check "install: cursor keeps other servers" jqe '.mcpServers.keep and .mcpServers["obsidian-memory"]' "$i/.cursor/mcp.json"
  check "install: vault path substituted" jqe --arg v "$i/vault" '.mcpServers["obsidian-memory"].args[-1] == ($v + "/claude-memory")' "$i/.cursor/mcp.json"
  check "install: opencode server added" jqe '.mcp["obsidian-memory"].type == "local"' "$i/.config/opencode/opencode.jsonc"
  check "install: codex table written once" test "$(grep -c '^\[mcp_servers.obsidian-memory\]' "$i/.codex/config.toml")" = 1
  check "install: codex pointer linked" test -L "$i/.codex/AGENTS.md"
  check "install: hermes mcp server set" jqe '.args[-1] | endswith("/claude-memory")' "$TMP/hcfg/mcp_servers.obsidian-memory"
  check "install: hermes recall hook added once, others kept" jqe 'length == 2 and .[0].command == "/other.sh" and (.[1].command | endswith("/memory-recall.sh"))' "$TMP/hcfg/hooks.pre_llm_call"
  check "install: hermes session-end commit hook" jqe '.[0].command | endswith("/vault-commit.sh")' "$TMP/hcfg/hooks.on_session_end"
  check "install: absent harness skipped" test ! -e "$i/Library/Application Support/Claude/claude_desktop_config.json"
}

test_recall() {
  local out
  mkdir -p "$TMP/rv/claude-memory/_global" "$TMP/rv/claude-memory/proj"
  echo '- [G](g.md) — global fact' >"$TMP/rv/claude-memory/_global/MEMORY.md"
  echo '- [P](p.md) — project fact' >"$TMP/rv/claude-memory/proj/MEMORY.md"
  out=$(recall "$(jq -nc --arg c "$H/dev/github/proj" '{cwd:$c,extra:{is_first_turn:true}}')")
  check "recall: first turn has global index" jqe '.context | test("global fact")' <<<"$out"
  check "recall: first turn has project index" jqe '.context | test("project fact")' <<<"$out"
  out=$(recall '{"extra":{"is_first_turn":false}}')
  check "recall: later turns inject nothing" test "$out" = '{}'
  out=$(recall "$(jq -nc --arg c "$H/dev/github/other" '{cwd:$c}')")
  check "recall: new project told where to save" jqe '.context | test("claude-memory/other/")' <<<"$out"
}

test_lint
test_folder_name
test_recall
test_link_hook
test_vault_commit
test_installer
finish
