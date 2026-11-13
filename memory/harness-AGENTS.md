# Shared memory

Garrett's long-term memory for every AI tool lives in the Obsidian vault at `/Users/garrett/dev/obsidian`. Read its `AGENTS.md` once for the format and rules.

At the start of each session:
1. Read `/Users/garrett/dev/obsidian/claude-memory/_global/MEMORY.md` (applies everywhere).
2. Read this repo's index: `/Users/garrett/dev/obsidian/claude-memory/<repo>/MEMORY.md`, where `<repo>` is the repo's name from its `origin` remote (e.g. `lumino-services`), the same for every clone and worktree; outside git, the working directory's name.
3. Open individual memory files when an index line is relevant.

When you learn something durable (a decision, a preference, a fact about the project), save it there in the same format and add its line to that folder's `MEMORY.md`. If you can't read files directly, the `obsidian-memory` MCP server gives access to `claude-memory/` only (not the vault root or its git repo); the format rules are repeated in `claude-memory/Claude Memory.md`.
