# `make check` is the definition of done. The global Stop hook runs it.
.PHONY: check fmt-check lint arch test web

check: fmt-check lint arch test web

fmt-check:
	@test -z "$$(gofmt -l $$(git ls-files '*.go'))" || { gofmt -l $$(git ls-files '*.go'); echo "gofmt needed"; exit 1; }

lint:
	golangci-lint run ./...

arch:
	@if command -v go-arch-lint >/dev/null; then go-arch-lint check; else echo "go-arch-lint not installed, skipping"; fi

test:
	go test -race ./...

# Runs only when a package.json exists (Next.js/TS projects).
web:
	@if [ -f package.json ]; then npm run --if-present typecheck && npm run --if-present lint; fi

# --- Performance (see perf-optimization-loop). Usage:
#   make bench-old BENCH=Scan PKG=./internal/ledger   # on the unchanged code
#   make bench-new BENCH=Scan PKG=./internal/ledger   # after one change
#   make bench-compare TOPIC=ledger-scan              # writes perf/ledger-scan.txt
BENCH ?= .
PKG ?= ./...
TOPIC ?= benchstat
.PHONY: bench-old bench-new bench-compare escape explain

bench-old:
	@mkdir -p perf && go test -run='^$$' -bench='$(BENCH)' -benchmem -count=10 $(PKG) > perf/old.txt

bench-new:
	@mkdir -p perf && go test -run='^$$' -bench='$(BENCH)' -benchmem -count=10 $(PKG) > perf/new.txt

bench-compare:
	benchstat perf/old.txt perf/new.txt | tee perf/$(TOPIC).txt

# Heap escapes in a package (justify every new one on a hot path).
escape:
	go build -gcflags='-m' $(PKG) 2>&1 | grep -E 'escapes to heap|moved to heap'

# EXPLAIN (ANALYZE, BUFFERS) through a read-only session (see postgres-query-review).
#   make explain Q=queries/list_tx.sql OUT=docs/explain/0007_tx_idx.txt
# EXPLAIN_DATABASE_URL must point at representative data with a read-only role.
explain:
	@test -n "$(Q)" && test -n "$(OUT)" || { echo "usage: make explain Q=file.sql OUT=docs/explain/<migration>.txt"; exit 1; }
	@mkdir -p "$$(dirname $(OUT))"
	PGOPTIONS='-c default_transaction_read_only=on' psql "$$EXPLAIN_DATABASE_URL" -X -v ON_ERROR_STOP=1 \
		-c "EXPLAIN (ANALYZE, BUFFERS) $$(cat $(Q))" | tee $(OUT)
