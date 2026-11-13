#!/bin/sh
# Print the vault memory folder for a working directory: the repo's name, so every
# clone and worktree of one repo shares one folder.
# Order: origin remote's name, then the main checkout's directory name, then the directory's own name.
# Usage: memory-folder.sh <dir>
dir=${1:-$PWD}
name=$(git -C "$dir" remote get-url origin 2>/dev/null)
if [ -z "$name" ]; then
  common=$(git -C "$dir" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
  case $common in
    */.git) name=${common%/.git} ;;
    ?*) name=$common ;; # bare repo
    *) name=$dir ;;
  esac
fi
name=${name%/}
name=${name##*/}
name=${name##*:} # scp-style remote with no path separator
name=${name%.git}
printf '%s' "$name" | tr -c 'A-Za-z0-9._-' '-'
