#!/usr/bin/env bash
# Wire this repo into Hermes Agent. Safe to run repeatedly; skipped without `hermes`.
#   1. skills.external_dirs gets ~/agents/skills (kept with any other dirs)
#   2. mcp_servers.mlflow, the MLflow MCP server Claude Code also runs (see README)
#   3. link hermes/plugins/agents-hooks into ~/.hermes/plugins and enable it:
#      the Claude Code hooks in claude/settings.json then run in Hermes too
# The memory pieces (obsidian-memory server, recall/commit hooks) are install-memory.sh's.
set -euo pipefail

AGENTS="$HOME/agents"
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
MLFLOW='{"command":"uv","args":["run","--with","mlflow[mcp]==3.18.0","mlflow","mcp","run"],"env":{"MLFLOW_TRACKING_URI":"http://localhost:5000"}}'

say() { printf '%s\n' "$*"; }

add_skills_dir() {
  local cur
  cur=$(hermes config get --json skills.external_dirs 2>/dev/null || true)
  jq -e 'type == "array"' <<<"$cur" >/dev/null 2>&1 || cur='[]'
  hermes config set skills.external_dirs "$(jq -c '. - ["~/agents/skills"] + ["~/agents/skills"]' <<<"$cur")" >/dev/null
  say "hermes: skills.external_dirs has ~/agents/skills"
}

link_plugin() {
  local link="$HERMES_HOME/plugins/agents-hooks" target="$AGENTS/hermes/plugins/agents-hooks"
  mkdir -p "$HERMES_HOME/plugins"
  if [ -L "$link" ] && [ "$(readlink "$link")" = "$target" ]; then
    say "ok:     $link"
  elif [ -e "$link" ] || [ -L "$link" ]; then
    say "SKIP:   $link exists and is not -> $target (move it aside, then re-run)" >&2
    return 0
  else
    ln -s "$target" "$link"
    say "linked: $link -> $target"
  fi
  hermes plugins enable agents-hooks >/dev/null
  say "hermes: plugin agents-hooks enabled"
}

main() {
  command -v hermes >/dev/null || { say "hermes: not installed, skipped"; return 0; }
  add_skills_dir
  hermes config set mcp_servers.mlflow "$MLFLOW" >/dev/null
  say "mcp:    hermes mcp_servers.mlflow"
  link_plugin
}

main "$@"
