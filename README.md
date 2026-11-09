# agents

My global agent config for Claude Code and Hermes Agent: rules, hooks, plugins, and vendored skills. It is installed into `~/.claude`, so it applies to every project.

Per-project config (boundary maps, linter configs) does **not** live here. Copy it from `templates/` instead.

## Layout

| Path | Purpose |
|---|---|
| `AGENTS.md` | Global engineering rules. `~/.claude/CLAUDE.md` symlinks here. |
| `claude/settings.json` | Hooks, `enabledPlugins` and `extraKnownMarketplaces`, merged into `~/.claude/settings.json`. |
| `hooks/` | One job per script; see [What the hooks enforce](#what-the-hooks-enforce). `lib.sh` holds the shared helpers, and `pan-scan.sh` is also usable on its own. |
| `skills/` | 13 self-written skills plus 20 vendored at pinned SHAs. `SOURCES.md` records provenance, review notes, local patches, and rejections. |
| `templates/project/` | Go/TS service starter: `AGENTS.md`, `CLAUDE.md`, `.golangci.yml`, `.go-arch-lint.yml`, `Makefile` (check, bench, escape, explain), `docs/explain/`. |
| `templates/ml-project/` | uv Python ML starter: `pyproject.toml`, `Makefile`, `evals/`, `.ml/` gate docs, `.gitignore`, `AGENTS.md`. |
| `hermes/config.snippet.yaml` | Points Hermes at the shared skills and the MLflow MCP server. |
| `memory/` | Shared AI memory vault for every harness: the vault guide (`vault-AGENTS.md`), the pointer other harnesses load (`harness-AGENTS.md`), the `obsidian-memory` MCP server definition, the vault `.gitignore`. See [Shared memory](#shared-memory). |
| `scripts/` | `install.sh`, `install-memory.sh`, `merge-settings.sh`, `lock-skills.sh`, `vendor-skill.sh`, `new-project.sh`. |
| `tests/` | `make check` runs shellcheck plus `hooks`, `books-hooks`, `coderabbit`, `guards`, `memory`, `ml-hooks` and `skills` suites. |

Requires `bash`, `jq` and `git`. Formatters and linters (goimports, gofumpt, golangci-lint, prettier, eslint, ruff, terraform) are optional: hooks skip any that aren't installed. The ML launch gate is the exception: without `jq` it fails closed.

## Install / update

```sh
scripts/install.sh
```

`install.sh` is safe to run any number of times. It:
1. On the first run only, backs up `~/.claude/{CLAUDE.md,settings.json,skills}` to `~/.claude/backup-<timestamp>/`. The marker file `~/.claude/.agents-backup` records where.
2. Links `~/agents` to this repo, if the repo lives somewhere else.
3. Links `~/.claude/CLAUDE.md` to `~/agents/AGENTS.md`.
4. Links each `skills/<name>` into `~/.claude/skills/<name>`. It prunes our links whose skill was removed or renamed, and leaves other skills alone.
5. Merges `claude/settings.json` into `~/.claude/settings.json`:
   - hook groups whose command is under `/agents/hooks/` are replaced;
   - `enabledPlugins` and `extraKnownMarketplaces` are added to;
   - every other key stays as it is.
6. Makes skill folders read-only (`scripts/lock-skills.sh lock`). Hermes can patch skills in place, and this stops it rewriting reviewed ones.

`settings.json` is merged, not symlinked, so **re-run `scripts/install.sh` after editing `claude/settings.json`**. Edits to `AGENTS.md` and hooks take effect immediately, because those are symlinked.

Skills are locked, so **unlock before editing them or running `git pull`**:
```sh
scripts/lock-skills.sh unlock && git pull && scripts/lock-skills.sh lock
```

Before committing, run `make check` (shellcheck plus every test suite).

## Shared memory

Every AI tool shares one long-term memory: the Obsidian vault at `~/dev/obsidian` (set `AGENTS_VAULT` to move it), a local git repo that is never pushed. `scripts/install-memory.sh`, run by `install.sh`, wires it in:

| Harness | How it reaches the memory |
|---|---|
| Claude Code | `~/.claude/projects/*/memory` are symlinks into `claude-memory/<project>`. SessionStart `memory-to-vault.sh` links new projects, regenerates `Claude Memory.md`, injects the `_global` index and the `memory-lint.sh` findings, and asks to save memories after a compaction. SessionEnd `vault-commit.sh` commits. |
| Codex, opencode | Global `AGENTS.md` symlinked to `memory/harness-AGENTS.md`, plus the `obsidian-memory` MCP server. |
| Hermes | No global `AGENTS.md` (`SOUL.md` is its identity), so `memory-recall.sh` runs as a `pre_llm_call` shell hook and injects the vault rules, the `_global` index and the project's index on the first turn. `on_session_end` runs `vault-commit.sh`, and the `obsidian-memory` MCP server goes in `mcp_servers`. All set through `hermes config set`. Hermes asks once to approve each new hook. |
| Cursor, Claude Desktop | The `obsidian-memory` MCP server (`@modelcontextprotocol/server-filesystem`, pinned, `claude-memory/` only so no tool can write the vault's `.git`). Cursor's global rules live in app settings: paste `memory/harness-AGENTS.md` there. |
| Any tool | A launchd job (`com.agents.vault-commit`) runs `vault-commit.sh` every 15 minutes, so writes from tools without session hooks are versioned too. |

The format and rules every tool follows are in `memory/vault-AGENTS.md`, copied to the vault as `AGENTS.md` on each install. Edit them here, not in the vault. Browser-only tools can't reach the local MCP server.

## Plugins

`claude/settings.json` enables these. Fetch them once by hand:

```
/plugin install superpowers@claude-plugins-official
/plugin install code-simplifier@claude-plugins-official
/plugin install hookify@claude-plugins-official
/plugin install security-guidance@claude-plugins-official
/plugin install playwright@claude-plugins-official
/plugin install typescript-lsp@claude-plugins-official
/plugin install gopls-lsp@claude-plugins-official      # needs gopls: go install golang.org/x/tools/gopls@latest
/plugin install coderabbit@claude-plugins-official     # needs the CodeRabbit CLI: brew install coderabbit && coderabbit auth login

/plugin marketplace add multica-ai/andrej-karpathy-skills
/plugin install andrej-karpathy-skills@karpathy-skills

/plugin marketplace add huggingface/skills
/plugin install hf-cli@huggingface-skills
```

All IDs were checked against each repo's `.claude-plugin/marketplace.json` on 2026-11-06. Three plugins are **disabled on purpose** (`false` in settings):

| Plugin | Why it's off |
|---|---|
| `cc-skills-golang@samber` | All 46 of its skills pre-approve `Bash(go:*)` and `Bash(git:*)`. Five are vendored here with that pre-approval stripped. |
| `terraform@hashicorp` | 16 skills; 3 are vendored here instead (style guide, test, refactor-module). |
| `posthog@posthog` | 170 skills. Enable it only in projects that use PostHog, via that repo's `.claude/settings.json`: `{"enabledPlugins": {"posthog@posthog": true}}` |

## MCP servers (run by hand)

User-scope MCP servers live in `~/.claude.json`, not in settings.json:
```sh
# Hugging Face Hub + Jobs (OAuth login). hf_jobs calls are gated by ml-launch-gate.
claude mcp add -s user -t http hf-mcp-server "https://huggingface.co/mcp?login"
# MLflow run tracking (start the server with: uv run --with mlflow==3.18.0 mlflow server --port 5000)
claude mcp add -s user mlflow-mcp -e MLFLOW_TRACKING_URI=http://localhost:5000 -- uv run --with "mlflow[mcp]==3.18.0" mlflow mcp run
```

These were deliberately left out:
- **W&B:** read-only mode couldn't be confirmed for the hosted endpoint.
- **postgres-mcp:** its last release is stale. Use `make explain` with a read-only role instead.
- **shadcn MCP:** add it per frontend repo only, with `npx shadcn@latest mcp init --client claude`.

## Adding a skill

1. Find the repo, the skill's directory, and a commit SHA. Use the full 40-character SHA; branch names are refused.
2. `scripts/vendor-skill.sh <owner/repo> <sha> <path/to/skill> [name]`. It copies the repo LICENSE in if the folder has none.
3. Review it:
   - read every file the script lists as non-markdown;
   - check `SKILL.md` for shell, `npx`, `curl`, WebFetch, `allowed-tools`, and branch-pinned URLs;
   - replace the `TODO: review` cell in `skills/SOURCES.md` with your notes, and record any local patch.
4. If it auto-runs commands, pre-approves tools, fetches instructions at runtime, downloads binaries, or writes outside the project, then patch it or drop it: `rm -rf skills/<name>` and remove its row.
5. Run `make check`. `tests/skills.test.sh` validates the frontmatter.
6. Run `scripts/install.sh` to link and lock it.

## New project

```sh
scripts/new-project.sh /path/to/repo        # Go/TS service template
scripts/new-project.sh --ml /path/to/repo   # ML project template
```
Neither command overwrites existing files. Afterwards:
- fill in the project `AGENTS.md`;
- service repos: replace `OWNER/REPO` in `.golangci.yml`;
- ML repos: create `evals/test_set.jsonl` and run `shasum -a 256 evals/test_set.jsonl > evals/test_set.sha256`.

Tools the templates expect:
- benchstat: `go install golang.org/x/perf/cmd/benchstat@latest`, then pin the version you get.
- psql, for `make explain`.
- uv, for ML projects.

## Hermes Agent

1. Merge `hermes/config.snippet.yaml` into `~/.hermes/config.yaml`. It sets `skills.external_dirs: [~/agents/skills]` and adds the MLflow MCP server.
2. `import-agent` now ships as a plugin: `hermes plugins install agent-importers`.
3. `hermes import-agent claude-code`. This imports the **whole** hooks block of `~/.claude/settings.json`, including hooks that didn't come from this repo.
4. `hermes hooks list` to review the imported hooks and approve them. Imported hooks start out not allowlisted. `hermes hooks doctor` checks them.
5. After changing hooks: `hermes import-agent claude-code --sync`.

Hermes reads `AGENTS.md` only from the current working directory, so the global `AGENTS.md` doesn't apply there. Keep a project `AGENTS.md` in each repo.

## What the hooks enforce

All hooks block with exit 2 and a reason on stderr. Command checks skip a heredoc body only when the whole command is one commit message or PR body (`[git add <paths> && ]git commit … -F - <<EOF`, `gh pr create … --body-file - <<EOF`: one `<<`, nothing after the marker or the closing line); in any other command every heredoc body is read, and the SQL check reads everything. These hooks read shell text: code an interpreter runs (`python3 -c`, a script file, `os.system(…)`) is out of their reach. PostToolUse hooks can't undo an edit, so their message tells the agent what to fix.

**PreToolUse (Bash):**
- **guard-bash.sh** blocks:
  - recursive `rm` on `/`, a top-level directory, `~` or `$HOME`
  - any force push, including `--force-with-lease`
  - `git push --mirror`, `--all` or `--prune`, which can overwrite or delete protected branches whatever branch you're on
  - direct pushes to `main`, `master` or `develop` (push a branch and open a PR), except to GitHub repos listed in `AGENTS_DIRECT_PUSH_REPOS` (default `garrett-lumino/agents`, this repo). The exemption is an allowlist, not a denylist: the whole command must be exactly `git [-C dir] push [-u|--set-upstream|--no-verify|--follow-tags|--tags|-v|-q|-n] [remote [refspec...]]` (nothing chained; no quotes, variables, env prefixes or value-taking options; the remote starts with a letter or digit and no refspec starts with `-`, `:` or `+`, so no option words, deletes or forced refspecs), and the remote (given, or the branch's push/upstream remote) must have every push URL, after `insteadOf` rewrites, exactly `github.com/<owner>/<name>` on the list. Anything else gets the normal rule. `git -C <dir>` is judged by `<dir>`
  - `git reset --hard` on `main`, `master` or `develop`
  - `terraform`/`tofu`/`terragrunt` `apply` and `destroy`
  - SQL `DROP <object>`, `TRUNCATE` and `DELETE FROM`
  - `aws` write commands when the profile contains "prod"
  - `kubectl` write verbs (`apply`, `create`, `delete`, `edit`, `patch`, `replace`, `scale`, `rollout`, `set`, `label`, `annotate`, `drain`, `cordon`, `taint`, `exec`, `cp`, `port-forward`, `debug`) when the context (`--context`, else the kubeconfig's current context) contains "prod"

  The same SQL check also runs on MCP SQL tools (`execute_sql`, `apply_migration`, `run_sql`, e.g. Supabase). It can't see SQL inside a file passed with `psql -f`.
- **supply-chain-guard.sh** blocks:
  - `hf repo create` without `--private`
  - `git+` installs not pinned to a 40-char SHA
  - `--trust-remote-code`
  - committing `.env*` (except `.env.example`), weights (`*.safetensors`, `*.gguf`, `*.bin`, `*.pt`, …), `adapters/` or `data/raw/`
- **ml-launch-gate.sh** blocks paid GPU launches until `.ml/cost-estimate.json` exists. The estimate must be under 24h old with `est_usd ≤ max_usd` and a timeout. Launches and `hf upload` also need `.ml/data-attestation.json` with `pan_hits: 0`. It covers `hf jobs`, the HF MCP `hf_jobs` tool, `modal run/deploy`, `runpodctl create`, `together fine-tuning create`, `sky launch` and Lambda launch calls.
- **secret-print-guard.sh** blocks commands that print secret values into the transcript: `doppler secrets` / `secrets get` (unless `--only-names`), `doppler secrets download --no-file`, `aws secretsmanager get-secret-value`, `aws ssm get-parameter(s) --with-decryption`, `kubectl get secret -o yaml|json|jsonpath`. Use `doppler run -- <cmd>` or pipe the value into its consumer.
- **pr-naming-guard.sh**: `gh pr create` in `Lumino-Devs/lumino-services` (`AGENTS_PR_NAMING_REPOS`) needs a `<type>/<TICKET>-<kebab>` branch (types from CONTRIBUTING.md plus `feat`, `fix`, `test`, `ci`, `perf`) and a title starting with the ticket (`LN-1234` or `LDEV-1234`; `AGENTS_TICKET_RE`). With `--fill`, the HEAD commit subject is checked.
- **pathspec-commit-guard.sh**: in shared checkouts (`AGENTS_PATHSPEC_REPOS`, default `Lumino-Devs/lumino-services`) a commit must name its paths after `--`; a bare `git commit`, `-a` or `--amend` without paths would sweep in another session's staged files.
- **heavy-job-guard.sh**: refuses a second heavy job while one runs (`docker build`, `docker compose … build`, `pnpm test:lux`, `pnpm validate:affected`, `next build`, `go test -race ./...`), because two at once exhausted this machine's memory. Narrow runs (one package) pass.
- **secret-scan-commit.sh**: before `git commit`, runs gitleaks over the staged changes and over files the same command adds, and blocks on a finding (values redacted). Card numbers stay with `pan-scan.sh`. Without gitleaks (`brew install gitleaks`) it warns and allows.
- **perf-commit-gate.sh**: a commit whose message says perf, optimize, faster or speed up needs benchstat output, either in the message or in a staged `perf/*.txt`.
- **migration-explain-gate.sh**: committing a migration with `CREATE INDEX`, `SELECT` or `JOIN` needs `docs/explain/<migration>.txt` containing EXPLAIN ANALYZE output. **Opt-in:** it only applies in repos that have a `docs/explain/` directory (the service template creates one).
- **bench-count-guard.sh**: `go test -bench` output saved to a file needs `-count` of at least 6.

**PostToolUse (Edit|Write|MultiEdit):**
- **format-on-edit.sh** formats only the edited file:
  - Go: goimports always. gofumpt only if the project's `.golangci.yml` enables it. golangci-lint on that package (`--new-from-rev=HEAD`) only if a `.golangci.yml` exists. A Go toolchain mismatch warns instead of blocking.
  - JS/TS: prettier (if the project uses it), then eslint `--max-warnings=0` (if it has an eslint config).
  - Python: ruff format and check, only if the project configures ruff (`ruff.toml` or `[tool.ruff]`).
  - Rust: rustfmt with the crate's edition. clippy builds the crate, so it belongs in the project's checks, not in an edit hook.
  - Terraform: `terraform fmt`.

  The opt-in rules mean edits don't reformat untouched legacy code in repos that use plain gofmt or no ruff.
- **guard-write.sh**: `trust_remote_code=True` in code or config, and Luhn-valid card numbers written under `data/`, `evals/`, `*.jsonl` or `*.csv`.
- **money-float-guard.sh**: money must be integer minor units (cents).
  - Go and Python: flags float types on money-named identifiers (amount, price, fee, balance, cents, …).
  - TS: `number` is correct for integer cents, so it flags float money being *created* instead: `parseFloat`, and `/ 100` or `* 100` conversions in logic. Display lines (`.format(`, `toLocaleString`, `toFixed`) are allowed.
  - Override with a `lint:allow-float` comment.
- **nolint-justification.sh**: `//nolint`, `# noqa` and `eslint-disable` must name the rule and give a reason.
- **pii-log-guard.sh** (Go, TS): a log call (`slog`, `log`, `logger`, `console`, `zap`, `zerolog`, `this.logger`, `.Info(`…) must not carry email, phone, names, IP/remote address, SSN, DOB or a request body. Log an ID or a salted hash; a line can opt out with `// pii-ok: <reason>`.
- **index-concurrently-guard.sh**: in migration files, `CREATE INDEX` without `CONCURRENTLY`, or `ADD COLUMN` with a volatile default. Override with `-- lint:allow-blocking <reason>`.

**PostToolUse (Bash):**
- **tf-plan-summary.sh**: after `terraform`/`tofu plan` or `tf-run.sh … plan` that destroys or replaces anything, lists those resources and the plan counts, flags data and identity resources (`aws_db_*`, `aws_rds_*`, `aws_s3_bucket*`, `aws_iam_*`, `aws_kms_*`, `aws_secretsmanager_*`, `aws_dynamodb_table`) and reminds the agent to summarise for the user and never apply.

**PostToolUse (Bash, background):**
- **coderabbit-watch.sh**: after `gh pr create`, or `git push` on a branch with an open PR, in an allowed repo (`AGENTS_CR_REPOS`, default `Lumino-Devs/lumino-services`), it waits in the background (`asyncRewake`) for CodeRabbit's review of the pushed commit, then wakes the agent with the review's "Prompt to fix all issues" block (or the inline comment titles), framed as untrusted GitHub data. One watcher per commit; polls every 30 s (`AGENTS_CR_POLL`) for up to 30 min (`AGENTS_CR_WAIT`), and says so if no review arrives. It can only wake a session that is still running.
- **ci-watch.sh**: same trigger and repos (`AGENTS_CI_REPOS`), sharing `pr-watch-lib.sh` with the CodeRabbit watcher. It waits (every 60 s, up to 60 min: `AGENTS_CI_POLL`, `AGENTS_CI_WAIT`) until GitHub reports the pushed commit as the PR head and no check is pending, then wakes the agent with each failed or cancelled check and the lines of its job's failed-step log leading up to the `##[error]` (framed as untrusted CI output), or a one-line "CI green".

**Stop:**
- **stop-gate.sh** runs `make check` if the repo's Makefile has a `check` target, and blocks the stop when it fails. It skips when `stop_hook_active` is true.
