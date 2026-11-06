# `make check` is the definition of done for this repo (the Stop hook runs it here too).
.PHONY: check lint test

check: lint test

lint:
	shellcheck -x hooks/*.sh scripts/*.sh tests/*.sh

test:
	@for t in tests/*.test.sh; do "$$t" || exit 1; done
