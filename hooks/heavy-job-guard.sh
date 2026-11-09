#!/usr/bin/env bash
# PreToolUse(Bash): one heavy job at a time. Parallel Docker builds and full test
# runs exhausted this machine's memory, so a second one waits for the first.
set -u
# shellcheck source=hooks/lib.sh
. "$(dirname "$0")/lib.sh"

# Heavy commands, as the agent types them and as they show in the process list.
HEAVY_CMD='(^|[;&|[:space:]])(docker([[:space:]]+buildx)?[[:space:]]+build|docker[[:space:]]+compose[[:space:]].*(build|--build)|pnpm[[:space:]]+(run[[:space:]]+)?(test:lux|validate:affected)|next[[:space:]]+build|go[[:space:]]+test[[:space:]].*-race.*[[:space:]]\./\.\.\.)([[:space:]]|$)'
HEAVY_PROC='docker( buildx)? build|docker compose .*(build|--build)|pnpm (run )?(test:lux|validate:affected)|next build|go test .*-race.* \./\.\.\.'

main() {
  local cmd running
  read_input
  cmd=$(json_get '.tool_input.command')
  [[ "$cmd" =~ $HEAVY_CMD ]] || exit 0
  have pgrep || exit 0
  running=$(pgrep -fl -- "$HEAVY_PROC" 2>/dev/null | head -n 3)
  [ -n "$running" ] || exit 0
  block "BLOCKED by heavy-job-guard: a heavy job is already running, and two at once exhaust this machine's memory:
$running
Wait for it to finish, or run a narrower command (one package: go test -race -p 2 <pkg>; turbo --concurrency=2)."
}

main
