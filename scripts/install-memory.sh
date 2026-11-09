#!/usr/bin/env bash
# Wire the shared AI memory vault into every installed harness. Safe to re-run.
#   1. vault: AGENTS.md, CLAUDE.md, .gitignore, local git repo
#   2. pointer AGENTS.md for Codex and opencode (symlinked to memory/harness-AGENTS.md)
#   3. obsidian-memory MCP server in Claude Desktop, Cursor, opencode and Codex
#   4. Hermes: MCP server, pre_llm_call memory-recall.sh, on_session_end vault-commit.sh
#   5. launchd job committing the vault every 15 minutes (macOS)
# The vault defaults to ~/dev/obsidian; override with AGENTS_VAULT.
set -euo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)
MEM="$REPO/memory"
VAULT="${AGENTS_VAULT:-$HOME/dev/obsidian}"
SERVER=$(jq -c --arg v "$VAULT" '.args |= map(gsub("\\$\\{VAULT\\}"; $v))' "$MEM/mcp-server.json")
NAME=$(jq -r .name <<<"$SERVER")

say() { printf '%s\n' "$*"; }

setup_vault() {
  mkdir -p "$VAULT/claude-memory/_global"
  cp "$MEM/vault-AGENTS.md" "$VAULT/AGENTS.md"
  printf '@AGENTS.md\n' >"$VAULT/CLAUDE.md"
  cp "$MEM/vault.gitignore" "$VAULT/.gitignore"
  if [ ! -d "$VAULT/.git" ]; then
    git -C "$VAULT" init -q
    git -C "$VAULT" add -A
    git -C "$VAULT" -c user.name="AI memory" -c user.email=noreply@localhost commit -qm "Vault: initial"
  fi
  say "vault:  $VAULT"
}

# link_pointer <file>: link a harness's global AGENTS.md to ours, if the harness is installed.
link_pointer() {
  local link="$1" target="$MEM/harness-AGENTS.md"
  [ -d "$(dirname "$link")" ] || return 0
  if [ -L "$link" ] && [ "$(readlink "$link")" = "$target" ]; then
    say "ok:     $link"
    return 0
  fi
  if [ -f "$link" ] && ! cmp -s "$link" "$target"; then
    say "SKIP:   $link has its own content; merge it into $target by hand" >&2
    return 0
  fi
  rm -f "$link"
  ln -s "$target" "$link"
  say "linked: $link -> $target"
}

# add_json_server <file> <jq filter using $s>: merge the server into a JSON config.
add_json_server() {
  local file="$1" filter="$2"
  [ -d "$(dirname "$file")" ] || return 0
  [ -s "$file" ] || printf '{}\n' >"$file"
  cp "$file" "$file.bak"
  if jq --argjson s "$SERVER" "$filter" "$file.bak" >"$file.tmp"; then
    mv "$file.tmp" "$file"
    say "mcp:    $file"
  else
    rm -f "$file.tmp"
    say "SKIP:   $file is not plain JSON (comments?); add $NAME by hand" >&2
  fi
}

add_codex_server() {
  local file="$HOME/.codex/config.toml"
  [ -d "$HOME/.codex" ] || return 0
  touch "$file"
  cp "$file" "$file.bak"
  # Drop any earlier copy of our table, then append the current one.
  awk -v h="[mcp_servers.$NAME]" '$0==h{skip=1;next} /^\[/{skip=0} !skip' "$file.bak" >"$file"
  jq -r '"[mcp_servers.\(.name)]\ncommand = \"\(.command)\"\nargs = [\(.args | map("\"" + . + "\"") | join(", "))]"' <<<"$SERVER" >>"$file"
  say "mcp:    $file"
}

# add_hermes_hook <event> <script>: append our hook to a Hermes hook list, keeping others.
add_hermes_hook() {
  local key="hooks.$1" cmd="$HOME/agents/hooks/$2" cur
  cur=$(hermes config get --json "$key" 2>/dev/null || true)
  case "$cur" in "" | "{}" | null | None | "[]") cur='[]' ;; esac
  if ! jq -e 'type == "array"' <<<"$cur" >/dev/null 2>&1; then
    say "SKIP:   hermes $key is not a JSON list; add $cmd by hand" >&2
    return 0
  fi
  hermes config set "$key" "$(jq -c --arg c "$cmd" 'map(select(.command != $c)) + [{command: $c, timeout: 15}]' <<<"$cur")" >/dev/null
  say "hermes: $key -> $cmd"
}

# Hermes has no global AGENTS.md (SOUL.md is its identity), so memory arrives
# through a pre_llm_call hook on the first turn, and commits at session end.
add_hermes() {
  command -v hermes >/dev/null || return 0
  hermes config set "mcp_servers.$NAME" "$(jq -c '{command, args}' <<<"$SERVER")" >/dev/null
  say "mcp:    hermes mcp_servers.$NAME"
  add_hermes_hook pre_llm_call memory-recall.sh
  add_hermes_hook on_session_end vault-commit.sh
}

install_launchd() {
  [ "$(uname)" = Darwin ] && [ -z "${AGENTS_NO_LAUNCHD:-}" ] || return 0
  local label=com.agents.vault-commit plist="$HOME/Library/LaunchAgents/com.agents.vault-commit.plist"
  mkdir -p "$(dirname "$plist")"
  cat >"$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$label</string>
  <key>ProgramArguments</key><array><string>$HOME/agents/hooks/vault-commit.sh</string></array>
  <key>EnvironmentVariables</key><dict>
    <key>AGENTS_VAULT</key><string>$VAULT</string>
    <key>PATH</key><string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
  </dict>
  <key>StartInterval</key><integer>900</integer>
  <key>StandardInputPath</key><string>/dev/null</string>
</dict></plist>
EOF
  launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "$plist"
  say "launchd: $label every 15 min"
}

# shellcheck disable=SC2016 # jq filters: $s is a jq variable, not a shell one
main() {
  setup_vault
  link_pointer "$HOME/.codex/AGENTS.md"
  link_pointer "$HOME/.config/opencode/AGENTS.md"
  local entry='{command: $s.command, args: $s.args}'
  add_json_server "$HOME/Library/Application Support/Claude/claude_desktop_config.json" ".mcpServers[\$s.name] = $entry"
  add_json_server "$HOME/.cursor/mcp.json" ".mcpServers[\$s.name] = $entry"
  add_json_server "$HOME/.config/opencode/opencode.jsonc" \
    '.mcp[$s.name] = {type: "local", command: ([$s.command] + $s.args), enabled: true}'
  add_codex_server
  add_hermes
  install_launchd
}

main "$@"
