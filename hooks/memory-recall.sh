#!/bin/sh
# Context hook for harnesses without native memory loading (Hermes pre_llm_call;
# any tool that pipes {"cwd": ...} JSON on stdin). On the first turn it prints
# {"context": ...} with the vault rules, the global index and this project's index.
VAULT="${AGENTS_VAULT:-$HOME/dev/obsidian}"
MEM="$VAULT/claude-memory"
input=$(cat)

first=$(printf '%s' "$input" | jq -r '([.extra.is_first_turn, .is_first_turn] | map(select(. != null)) + [true])[0]' 2>/dev/null)
[ "$first" = false ] && { printf '{}\n'; exit 0; }
[ -d "$MEM" ] || { printf '{}\n'; exit 0; }

cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
[ -n "$cwd" ] || cwd=$PWD
# Same folder naming as Claude Code: non-alphanumerics become "-", then drop the home prefix.
prefix=$(printf '%s' "$HOME/dev/github/" | tr -c 'A-Za-z0-9' '-')
project=$(printf '%s' "$cwd" | tr -c 'A-Za-z0-9' '-')
project=${project#"$prefix"}
project=${project#-}

context=$(
  printf 'Shared long-term memory lives in %s (format and rules: %s/AGENTS.md).\n' "$MEM" "$VAULT"
  printf 'Open a memory file when its index line is relevant. Save durable facts there in the same format and add the index line.\n\n'
  printf '## Global memory (%s/_global)\n' "$MEM"
  head -n 200 -- "$MEM/_global/MEMORY.md" 2>/dev/null
  if [ -f "$MEM/$project/MEMORY.md" ]; then
    printf '\n## Project memory (%s/%s)\n' "$MEM" "$project"
    head -n 200 -- "$MEM/$project/MEMORY.md"
  else
    printf '\nNo project memory yet. Save this project'"'"'s memories in %s/%s/ with a MEMORY.md index.\n' "$MEM" "$project"
  fi
)
jq -n --arg c "$context" '{context: $c}'
