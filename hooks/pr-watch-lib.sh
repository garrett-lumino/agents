#!/usr/bin/env bash
# Shared by the PR watchers (sourced, not a hook): which PR a `gh pr create` or
# `git push` just touched, and how to wake the agent.

# pr_watch_target <hook input JSON> <allowed repos> <watcher name>: for `gh pr create` or
# `git push` in an allowed repo with an open PR, set PW_REPO PW_NUMBER PW_URL PW_SHA and take
# this watcher's lock for the commit (one watcher per commit). Fails for anything else.
# shellcheck disable=SC2034  # PW_* are read by the watchers that source this file
pr_watch_target() {
  local cmd pr state="${XDG_CACHE_HOME:-$HOME/.cache}/agents/$3"
  cmd=$(jq -r '.tool_input.command // empty' <<<"$1" 2>/dev/null)
  case "$cmd" in *"gh pr create"* | *"git push"*) ;; *) return 1 ;; esac
  cd "$(jq -r '.cwd // empty' <<<"$1")" 2>/dev/null || return 1
  PW_REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null) || return 1
  case " $2 " in *" $PW_REPO "*) ;; *) return 1 ;; esac
  pr=$(gh pr view --json number,url -q '"\(.number) \(.url)"' 2>/dev/null) || return 1
  PW_NUMBER=${pr%% *} PW_URL=${pr#* }
  PW_SHA=$(git rev-parse HEAD 2>/dev/null) || return 1
  mkdir -p "$state" && mkdir "$state/${PW_REPO//\//_}-$PW_NUMBER-$PW_SHA" 2>/dev/null
}

# pw_wake <message> <max chars>: wake the agent (asyncRewake: exit 2 with the message on stderr).
pw_wake() {
  printf '%s\n' "$1" | head -c "$2" >&2
  exit 2
}
