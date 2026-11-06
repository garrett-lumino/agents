# <Project name>: Agent Rules

Global rules live in `~/agents/AGENTS.md`. This file adds this repo's boundary map. Delete the sections that don't apply.

## Commands
- `make check`: the definition of done (format check, lint, architecture lint, tests).
- `make test`: tests only.

## Go layer map
```
cmd/<app>/              wiring only: parse config, build adapters, inject into domain, start
internal/<domain>/      pure business logic and the interfaces it needs (ports)
internal/adapters/
  postgres/             implements domain ports with pgx/sqlc
  http/                 handlers: decode → call domain → encode
  aws/                  SDK clients behind domain ports
```
Rules (enforced by `.go-arch-lint.yml`):
- `cmd` may import anything.
- `internal/adapters/*` may import `internal/<domain>`, never each other.
- `internal/<domain>` imports only the stdlib and other domain packages, never adapters, `database/sql`, `net/http`, or the AWS SDK.

## Next.js layer map
```
app/                    routes and layouts only: thin, call into features
features/<name>/        components, hooks, server actions, and logic for one feature
                        (or colocate them in the route folder; pick one per repo and say which here)
components/ui/          shared primitives (shadcn), no business logic
lib/                    framework-agnostic clients (db, auth), no feature logic
```
Rules:
- No imports from one `features/<a>` into another `features/<b>`. Lift the shared piece to `components/ui` or `lib`.
- `components/ui` never imports from `features`.

## Domain glossary
- <Term>: <one-line meaning>

## Project-specific constraints
- <e.g. "All money is int64 cents", "Migrations live in db/migrations and are forward-only">
