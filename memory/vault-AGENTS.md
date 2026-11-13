# AI memory vault

This vault is the shared, long-term memory for every AI tool Garrett uses (Claude Code, Codex, Cursor, opencode, MCP clients). Garrett does not edit it by hand. Tools read and write it. It is a local git repo (never pushed); history is the safety net, so commit-worthy mistakes can be rolled back.

## Layout

- `claude-memory/_global/`: memories that apply to every project. Load its `MEMORY.md` at the start of every session.
- `claude-memory/<repo>/<feature>/<memory>.md`: memories for one code repo. The folder is the repo's name (its `origin` remote, e.g. `lumino-services`), shared by every clone and worktree of it; a hook never makes a folder per worktree. Feature subfolders group related memories (`lumino-services/lux/`, `lumino-services/ci-cd/`). Claude Code reaches these through `~/.claude/projects/*/memory` symlinks.
- `claude-memory/<topic>/<specific>/<memory>.md`: reference banks not tied to one repo (`payment-processors/adyen/`, `omnivenue/ledger/`).
- `claude-memory/claude-ai/`: Garrett's claude.ai memory (profile, preferences, people, areas, claude.ai Projects), imported 2026-11-08 and flattened into this format; each file's `metadata.source` names its original path. Not tied to one project; the `_global` index points to it.
- `claude-memory/Claude Memory.md`: generated index of folders. Never edit it; a hook rewrites it.

## Memory format

Each repo or topic folder has a `MEMORY.md` index with one line per memory, grouped under feature headings, linking relative paths:

```
## Lux
- [Short title](lux/file-name.md) — one-line hook
```

A large subfolder may have its own `MEMORY.md`, linked from the parent index (`- [Adyen memory bank](adyen/MEMORY.md) — …`). Keep each repo's root index under 200 lines; Claude Code loads only that file.

Every other `.md` file holds one fact:

```markdown
---
name: file-name            # kebab-case, equals the filename without .md
description: one-line summary used to decide relevance
metadata:
  type: user | feedback | project | reference
---

The fact. For feedback and project memories, follow with **Why:** and **How to apply:** lines.
Link related memories with [[their-name]].
```

## Rules for every tool

- Put a new memory in the feature or topic subfolder it belongs to (create one when none fits); never make a folder per worktree or branch.
- Add the `MEMORY.md` line in the same change as the file. A file missing from the index is never loaded.
- Check for an existing memory before writing a new one; update it rather than duplicating.
- Write dates as absolute dates (2026-11-08), never "today" or "last week".
- Don't delete another tool's memory. If it's wrong, correct it, or mark it superseded and link the replacement.
- No secrets, tokens, card numbers or customer PII in memory.
- Keep each memory to one fact. Put something that applies everywhere in `_global/`, not in a project folder.
