#!/usr/bin/env bash
# PreToolUse(Bash): block destructive commands before they run.
set -u
# shellcheck source=hooks/lib.sh
. "$(dirname "$0")/lib.sh"

deny() { block "BLOCKED by guard-bash: $1
  command: $2
Ask the user to run it themselves if it is really intended."; }

lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# Drop quotes and trailing "/" or "/*" so "~/", "$HOME/*" and "/" normalize.
normalize_path() {
  local t="${1//\"/}"
  t="${t//\'/}"
  while :; do
    case "$t" in
      */\*) t="${t%/\*}" ;;
      */) t="${t%/}" ;;
      *) break ;;
    esac
  done
  printf '%s' "$t"
}

is_home_or_root() {
  local t
  t=$(normalize_path "$1")
  # shellcheck disable=SC2016  # match the literal text "$HOME" too
  case "$t" in
    '' | '~' | '$HOME' | '${HOME}' | "$HOME") return 0 ;;
    /Users/*/* | /home/*/*) return 1 ;;
    /Users/* | /home/* | /root) return 0 ;;
    /*/*) return 1 ;;
    /*) return 0 ;;
  esac
  return 1
}

check_rm() {
  local seg="$1" w flags="" words
  set -f
  read -r -a words <<<"$seg"
  set +f
  [ "${words[0]:-}" = sudo ] && words=("${words[@]:1}")
  [ "${words[0]:-}" = rm ] || return 0
  for w in "${words[@]:1}"; do
    case "$w" in
      --recursive) flags="${flags}r" ;;
      --*) ;;
      -*) flags="$flags${w#-}" ;;
    esac
  done
  case "$flags" in *[rR]*) ;; *) return 0 ;; esac
  for w in "${words[@]:1}"; do
    case "$w" in -*) continue ;; esac
    is_home_or_root "$w" && deny "recursive rm on a home or root path ($w)" "$seg"
  done
  return 0
}

is_protected_branch() {
  case "$1" in main | master | develop) return 0 ;; esac
  return 1
}

current_branch() { git -C "${1:-.}" symbolic-ref --short HEAD 2>/dev/null; }

# Branch a push refspec lands on: "+HEAD:refs/heads/main" -> main, "HEAD" -> current.
push_dest() {
  local ref="${1#+}" cwd="$2"
  ref="${ref##*:}"
  ref="${ref#refs/heads/}"
  [ "$ref" = HEAD ] && ref=$(current_branch "$cwd")
  printf '%s' "$ref"
}

# GitHub repos (owner/name) whose protected branches may take direct pushes.
DIRECT_PUSH_REPOS="${AGENTS_DIRECT_PUSH_REPOS:-garrett-lumino/agents}"

# github_repo <url>: owner/name of a github.com https/ssh/scp URL; nothing for anything else.
github_repo() {
  printf '%s' "$1" | sed -nE 's#^(https://|ssh://git@|git@)github\.com[:/]([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)$#\2#p' | sed 's#\.git$##'
}

is_listed_repo() {
  local entry
  for entry in $DIRECT_PUSH_REPOS; do [ "$1" = "$entry" ] && return 0; done
  return 1
}

# The only command shape the exemption accepts, whole: `git [-C dir] push [flags] [remote [refspec...]]`,
# with no chaining, quoting, variables, env prefixes, value-taking options or forced (+) refspecs.
PUSH_FLAGS='(-u|--set-upstream|--no-verify|--follow-tags|--tags|-v|--verbose|-q|--quiet|-n|--dry-run)'
PLAIN_PUSH="^[[:space:]]*git( +-C +[A-Za-z0-9._/~-]+)? +push( +$PUSH_FLAGS)*( +[A-Za-z0-9._-]+( +[A-Za-z0-9._/:@^~-]+)*)?[[:space:]]*$"

# push_target <cmd> <cwd>: print "<repo dir>\t<remote>" for a command matching PLAIN_PUSH.
push_target() {
  local dir="$2" words w prev="" seen=0 remote="" branch
  [[ "$1" =~ $PLAIN_PUSH ]] || return 1
  read -r -a words <<<"$1"
  for w in "${words[@]}"; do
    if [ "$seen" = 0 ]; then
      [ "$prev" = -C ] && case "$w" in /*) dir=$w ;; "~"*) dir="$HOME${w#\~}" ;; *) dir="$dir/$w" ;; esac
      [ "$w" = push ] && seen=1
      prev=$w
      continue
    fi
    case "$w" in -*) continue ;; esac
    remote=$w
    break
  done
  if [ -z "$remote" ]; then
    branch=$(current_branch "$dir") || return 1
    remote=$(git -C "$dir" config "branch.$branch.pushRemote" || git -C "$dir" config remote.pushDefault ||
      git -C "$dir" config "branch.$branch.remote" || echo origin)
  fi
  printf '%s\t%s' "$dir" "$remote"
}

# push_exempt <cwd> <cmd>: true only when the whole command is one plain push that
# certainly lands on a listed repo.
push_exempt() {
  local target dir remote urls url repo
  target=$(push_target "$2" "$1") || return 1
  dir=${target%%$'\t'*} remote=${target#*$'\t'}
  # A named remote only (a raw URL is not one); every push URL must be a listed repo.
  urls=$(git -C "$dir" remote get-url --push --all "$remote" 2>/dev/null) && [ -n "$urls" ] || return 1
  while IFS= read -r url; do
    repo=$(github_repo "$url")
    [ -n "$repo" ] && is_listed_repo "$repo" || return 1
  done <<<"$urls"
  return 0
}

# Direct pushes to main/master/develop go through a PR instead.
check_push_target() {
  local seg="$1" cwd="$2" words w prev="" seen=0 pos=0 tags=0 dest
  push_exempt "$cwd" "$3" && return 0
  set -f
  read -r -a words <<<"$seg"
  set +f
  for w in "${words[@]}"; do
    if [ "$seen" = 0 ]; then
      [ "$prev" = -C ] && cwd="${w/#\~/$HOME}" # `git -C <dir>` names the repo for the branch checks
      [ "$w" = push ] && seen=1
      prev=$w
      continue
    fi
    case "$w" in
      --tags) tags=1 ;;
      -*) ;;
      *)
        pos=$((pos + 1))
        [ "$pos" -ge 2 ] || continue # first positional is the remote
        dest=$(push_dest "$w" "$cwd")
        is_protected_branch "$dest" && deny "direct push to $dest (open a PR)" "$seg"
        ;;
    esac
  done
  [ "$pos" -ge 2 ] || [ "$tags" = 1 ] && return 0
  dest=$(current_branch "$cwd")
  is_protected_branch "$dest" && deny "direct push to $dest (open a PR)" "$seg"
  return 0
}

check_git() {
  local seg="$1" cwd="$2" cmd="$3" branch
  printf '%s' "$seg" | grep -Eq '(^|[[:space:]])git([[:space:]]|$)' || return 0
  if printf '%s' "$seg" | grep -Eq '[[:space:]]push([[:space:]]|$)'; then
    printf '%s' "$seg" | grep -Eq '[[:space:]](--force[^[:space:]]*|-[a-zA-Z]*f[a-zA-Z]*)([[:space:]]|$)' &&
      deny "force push" "$seg"
    check_push_target "$seg" "$cwd" "$cmd"
  fi
  printf '%s' "$seg" | grep -Eq '[[:space:]]reset[[:space:]].*--hard|--hard.*[[:space:]]reset([[:space:]]|$)' || return 0
  branch=$(current_branch "$cwd")
  is_protected_branch "$branch" && deny "git reset --hard on $branch" "$seg"
  return 0
}

check_terraform() {
  printf '%s' "$1" |
    grep -Eq '(^|[[:space:]])(terraform|tofu|terragrunt)([[:space:]]+[^[:space:]]+)*[[:space:]]+(apply|destroy)([[:space:]]|$)' &&
    deny "terraform apply/destroy" "$1"
  return 0
}

# Checked against the whole command so SQL inside heredocs and pipes is caught.
check_sql() {
  local objects='table|database|schema|view|materialized|index|column|constraint|function|procedure|trigger|type|sequence|extension|role|user|owned|policy'
  printf '%s' "$1" | grep -Eiq "(^|[^[:alnum:]_])drop[[:space:]]+($objects)([^[:alnum:]_]|$)" &&
    deny "SQL DROP (show the SQL to the user instead)" "$1"
  printf '%s' "$1" | grep -Eiq '(^|[^[:alnum:]_])delete[[:space:]]+from([^[:alnum:]_]|$)' &&
    deny "SQL DELETE (show the SQL to the user instead)" "$1"
  # Skip the coreutils `truncate` command (first word), keep SQL TRUNCATE.
  printf '%s' "$1" | sed -E 's/^[[:space:]]*truncate[[:space:]]//; s/([;&|][[:space:]]*)truncate[[:space:]]/\1/g' |
    grep -Eiq '(^|[^[:alnum:]_-])truncate[[:space:]]+(table[[:space:]]+|only[[:space:]]+)?[a-z_"]' &&
    deny "SQL TRUNCATE (show the SQL to the user instead)" "$1"
  return 0
}

is_aws_read_op() {
  case "$1" in
    describe-* | list-* | get-* | head-* | ls | wait | help | presign | tail | \
      filter-log-events | lookup-events | search-* | scan | query | batch-get-* | \
      test-* | validate-* | estimate-* | simulate-* | preview-*) return 0 ;;
  esac
  return 1
}

check_aws() {
  local seg="$1" words w i=0 profile="${AWS_PROFILE:-${AWS_DEFAULT_PROFILE:-}}" args=()
  set -f
  read -r -a words <<<"$seg"
  set +f
  while [ "$i" -lt "${#words[@]}" ]; do
    w="${words[$i]}"
    case "$w" in
      AWS_PROFILE=* | AWS_DEFAULT_PROFILE=*) profile="${w#*=}" ;;
      --profile) i=$((i + 1)) && profile="${words[$i]:-}" ;;
      --profile=*) profile="${w#*=}" ;;
      --debug | --no-* | --dryrun | --dry-run | --*=*) ;;
      --*) i=$((i + 1)) ;;
      *) args+=("$w") ;;
    esac
    i=$((i + 1))
  done
  [ "${args[0]:-}" = aws ] || return 0
  case "$(lower "$profile")" in *prod*) ;; *) return 0 ;; esac
  case "${args[1]:-}" in configure | help | sts) return 0 ;; esac
  is_aws_read_op "${args[2]:-}" || deny "aws write command against prod profile '$profile'" "$seg"
  return 0
}

main() {
  local cmd cwd seg
  read_input
  # Bash passes .command; SQL MCP tools (execute_sql, apply_migration) pass .query.
  cmd=$(json_get '.tool_input.command // .tool_input.query // .tool_input.sql')
  cwd=$(json_get '.cwd')
  [ -n "$cmd" ] || exit 0
  check_sql "$cmd"
  # shellcheck disable=SC2020  # per-char on purpose: ; & | each end a segment
  while IFS= read -r seg; do
    check_rm "$seg"
    check_git "$seg" "$cwd" "$cmd"
    check_terraform "$seg"
    check_aws "$seg"
  done < <(printf '%s\n' "$cmd" | tr ';&|' '\n\n\n')
  exit 0
}

main
