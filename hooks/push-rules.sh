#!/usr/bin/env bash
# Push rules for guard-bash.sh (sourced, not a hook): protected branches, the
# direct-push exemption, and reading push arguments the way git does.

is_protected_branch() {
  case "$1" in main | master | develop) return 0 ;; esac
  return 1
}

current_branch() { git -C "${1:-.}" symbolic-ref --short HEAD 2>/dev/null; }

# Branch a refspec lands on, read the way git reads it:
# "+HEAD:refs/heads/main" -> main, "HEAD:heads/main" -> main, "HEAD" -> the current branch.
push_dest() {
  local ref="${1#+}" cwd="$2"
  ref="${ref##*:}"
  ref="${ref#refs/heads/}"
  ref="${ref#heads/}"
  [ "$ref" = HEAD ] && ref=$(current_branch "$cwd")
  printf '%s' "$ref"
}

# A destination is protected when its last path part is a protected branch name.
lands_on_protected() { is_protected_branch "${1##*/}"; }

# Push options the guard reads; anything else, or an abbreviation git would expand, is refused.
PUSH_OPTS=" --set-upstream --no-verify --follow-tags --tags --delete --dry-run --verbose --quiet --atomic --porcelain --progress --no-progress "
PUSH_SHORT='^-[uvqnd]+$'
# A remote or refspec word: plain characters only (no quotes, globs, $), and no empty destination.
PUSH_WORD='^[+]?[A-Za-z0-9._/@^~-]*(:[A-Za-z0-9._/@^~-]+)?$'

# With no refspec on the command line, configured push refspecs or mirroring decide what is sent.
push_config_risky() {
  git -C "$1" config --get-regexp '^remote\..*\.(push|mirror)$' >/dev/null 2>&1 && return 0
  [ "$(git -C "$1" config push.default 2>/dev/null)" = matching ]
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
# with no chaining, quoting, variables, env prefixes, value-taking options, deletes or forced refspecs.
PUSH_FLAGS='(-u|--set-upstream|--no-verify|--follow-tags|--tags|-v|--verbose|-q|--quiet|-n|--dry-run)'
# Remote and refspec words never start with "-" (an option), ":" (a delete) or "+" (a force).
PLAIN_PUSH="^[[:space:]]*git( +-C +[A-Za-z0-9._/~-]+)? +push( +$PUSH_FLAGS)*( +[A-Za-z0-9][A-Za-z0-9._-]*( +[A-Za-z0-9._/@^~][A-Za-z0-9._/:@^~-]*)*)?[[:space:]]*$"

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

# Direct pushes to main/master/develop go through a PR instead. Anything the guard
# can't read with certainty is refused rather than guessed at.
check_push_target() {
  local seg="$1" cwd="$2" words w prev="" seen=0 pos=0 tags=0 dest
  push_exempt "$cwd" "$3" && return 0
  set -f
  read -r -a words <<<"$seg"
  set +f
  for w in "${words[@]}"; do
    if [ "$seen" = 0 ]; then
      [ "$prev" = -C ] && cwd="${w/#\~/$HOME}" # `git -C <dir>` names the repo for the branch checks
      case "$w" in -c* | --config-env*) deny "git -c on a push (config can change what is pushed)" "$seg" ;; esac
      [ "$w" = push ] && seen=1
      prev=$w
      continue
    fi
    check_push_word "$w" "$seg" "$cwd" "$pos" || { pos=$((pos + 1)); continue; }
    [ "$w" = --tags ] && tags=1
  done
  [ "$pos" -ge 2 ] || [ "$tags" = 1 ] && return 0
  push_config_risky "$cwd" && deny "push with configured push refspecs, mirroring or push.default=matching" "$seg"
  dest=$(current_branch "$cwd")
  lands_on_protected "$dest" && deny "direct push to $dest (open a PR)" "$seg"
  return 0
}

# check_push_word <word> <seg> <cwd> <positionals so far>: deny what can't be read or lands on a
# protected branch. Returns 1 for a positional word (remote or refspec), 0 for an option.
check_push_word() {
  local w="$1" seg="$2" dest
  case "$w" in
    -*)
      [[ "$w" =~ $PUSH_SHORT ]] && return 0
      case "$PUSH_OPTS" in *" $w "*) return 0 ;; esac
      deny "push option $w is not on the guard's list" "$seg"
      ;;
  esac
  [[ "$w" =~ $PUSH_WORD ]] || deny "can't read push argument $w" "$seg"
  [ "$4" -ge 1 ] || return 1 # first positional is the remote
  dest=$(push_dest "$w" "$3")
  lands_on_protected "$dest" && deny "direct push to $dest (open a PR)" "$seg"
  return 1
}
