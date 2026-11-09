# Shared memory

Garrett's long-term memory for every AI tool lives in the Obsidian vault at `/Users/garrett/dev/obsidian`. Read its `AGENTS.md` once for the format and rules.

At the start of each session:
1. Read `/Users/garrett/dev/obsidian/claude-memory/_global/MEMORY.md` (applies everywhere).
2. Read this project's index: `/Users/garrett/dev/obsidian/claude-memory/<project>/MEMORY.md`, where `<project>` is the absolute working directory with `/` replaced by `-`, minus the leading `-Users-garrett-dev-github-` (e.g. `/Users/garrett/dev/github/pour` → `pour`).
3. Open individual memory files when an index line is relevant.

When you learn something durable (a decision, a preference, a fact about the project), save it there in the same format and add its line to that folder's `MEMORY.md`. The `obsidian-memory` MCP server gives file access to the vault if you can't read files directly.
