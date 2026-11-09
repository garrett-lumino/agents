#!/usr/bin/env bash
# Shared hook helpers. Source this file; it has no side effects.

HOOK_INPUT=""

have() { command -v "$1" >/dev/null 2>&1; }

log() {
  [ -n "${AGENTS_HOOK_DEBUG:-}" ] && printf '[hook] %s\n' "$*" >&2
  return 0
}

# Exit 2 with the reason on stderr; Claude Code and Hermes treat this as a block.
block() {
  printf '%s\n' "$*" >&2
  exit 2
}

# Read the hook JSON from stdin. Without jq we cannot parse it, so warn and allow.
read_input() {
  have jq || { printf 'warning: jq not installed; %s skipped\n' "$(basename "$0")" >&2; exit 0; }
  HOOK_INPUT=$(cat)
}

# Same, but fail closed: for gates where "couldn't check" must mean "no".
read_input_strict() {
  have jq || block "BLOCKED: jq not installed, so $(basename "$0") cannot verify this action."
  HOOK_INPUT=$(cat)
}

# json_get '.tool_input.command' -> value, or empty string if missing.
json_get() {
  printf '%s' "$HOOK_INPUT" | jq -r "$1 // empty" 2>/dev/null
}

# Directory the agent is working in (hook JSON cwd, else $PWD).
hook_cwd() {
  local d
  d=$(json_get '.cwd')
  printf '%s' "${d:-$PWD}"
}

# Repo root containing <dir>, or <dir> itself outside git.
repo_root() {
  git -C "$1" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$1"
}

# New text written by Edit / Write / MultiEdit, one blob.
edited_text() {
  printf '%s' "$HOOK_INPUT" | jq -r '
    [.tool_input.content, .tool_input.new_string, (.tool_input.edits[]?.new_string)]
    | map(select(. != null)) | join("\n")' 2>/dev/null
}

# github_repo <url>: owner/name of a github.com https/ssh/scp URL; nothing for anything else.
github_repo() {
  printf '%s' "$1" | sed -nE 's#^(https://|ssh://git@|git@)github\.com[:/]([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)$#\2#p' | sed 's#\.git$##'
}

# origin_repo <dir>: owner/name of the GitHub repo that <dir>'s origin points at, or nothing.
origin_repo() {
  github_repo "$(git -C "$1" remote get-url origin 2>/dev/null)"
}

# in_list <word> <space-separated list>: exact membership.
in_list() {
  local entry
  for entry in $2; do [ "$1" = "$entry" ] && return 0; done
  return 1
}

is_git_commit() {
  printf '%s' "$1" | grep -Eq '(^|[;&|[:space:]])git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+commit([[:space:]]|$)'
}

# is_commit <text>: a git commit, with any git global options before `commit`.
is_commit() {
  [[ "$1" =~ (^|[\;\&\|[:space:]])git([[:space:]]+-[^[:space:]]+([[:space:]]+[^-[:space:]][^[:space:]]*)?)*[[:space:]]+commit([[:space:]]|$) ]]
}

# resolve_dir <dir> <base>: an absolute path, or nothing when the shell could rewrite it.
resolve_dir() {
  local d="$1"
  [[ "$d" =~ [\"\'\$\`\\*?[{] ]] && return 1
  d="${d/#\~/$HOME}"
  [[ "$d" == /* ]] || d="$2/$d"
  printf '%s' "$d"
}

# commit_c_dirs <commit segment> <dir>: <dir> after the segment's git -C options (-C <d>, -C<d>,
# any number, anywhere before `commit`).
commit_c_dirs() {
  local words w i=0 dir="$2" d in_git=0
  set -f
  read -r -a words <<<"$1"
  set +f
  while [ "$i" -lt "${#words[@]}" ]; do
    w="${words[$i]}"
    i=$((i + 1))
    if [ "$in_git" = 0 ]; then
      # Only VAR=value may come before git; a wrapper (env -C, sudo, ...) could move the repo.
      [ "$w" = git ] && in_git=1 && continue
      [[ "$w" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]] || return 1
      continue
    fi
    [ "$w" = commit ] && break
    case "$w" in
      -C) d="${words[$i]:-}" && i=$((i + 1)) ;;
      -C?*) d="${w#-C}" ;;
      *) continue ;;
    esac
    dir=$(resolve_dir "$d" "$dir") || return 1
  done
  printf '%s' "$dir"
}

# commit_root <cmd> <cwd>: the repo the commit runs in, following plain `cd <dir>` segments
# before it and git -C options; fails for anything else that could move it (quoted or
# grouped cd, pushd/popd forms it can't read, wrappers before git, --git-dir, --work-tree,
# GIT_DIR, core.worktree/gitdir config, --namespace).
commit_root() {
  local dir="$2" seg
  [[ "$1" =~ --git-dir|--work-tree|GIT_DIR|GIT_WORK_TREE|worktree|gitdir|--namespace ]] && return 1
  # shellcheck disable=SC2020  # per-char on purpose: ; & | each end a segment
  while IFS= read -r seg; do
    if is_commit "$seg"; then
      dir=$(commit_c_dirs "$seg" "$dir") || return 1
      break
    elif [[ "$seg" =~ ^[[:space:]]*(cd|pushd)[[:space:]]+([^[:space:]]+)[[:space:]]*$ ]]; then
      dir=$(resolve_dir "${BASH_REMATCH[2]}" "$dir") || return 1
    elif printf '%s' "$seg" | tr -d "\"'\\\\" | grep -Eq '(^|[^[:alnum:]_])(cd|pushd|popd)([^[:alnum:]_]|$)'; then
      return 1
    fi
  done < <(printf '%s\n' "$1" | tr ';&|' '\n\n\n')
  repo_root "$dir"
}

# Files a git command is about to commit, relative to the repo root: everything
# staged, plus every changed/untracked file when the command also runs `git add`
# or `commit -a` (over-approximates, which is the safe direction for a gate).
pending_files() {
  local root="$1" cmd="$2"
  git -C "$root" diff --cached --name-only 2>/dev/null
  if printf '%s' "$cmd" | grep -Eq '(^|[;&|[:space:]])git[[:space:]]+add([[:space:]]|$)|git[[:space:]]+commit[[:space:]]+(.*[[:space:]])?(-[a-zA-Z]*a[a-zA-Z]*|--all)([[:space:]]|$)'; then
    git -C "$root" status --porcelain -uall 2>/dev/null | sed -E 's/^.. //; s/.* -> //'
  fi
}
