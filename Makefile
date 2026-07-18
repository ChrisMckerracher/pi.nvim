HOST := host
STYLUA := $(shell command -v stylua 2>/dev/null || echo $(HOME)/.local/share/nvim/mason/bin/stylua)
SELENE := $(shell command -v selene 2>/dev/null)

.PHONY: install build lint test check

install:
	npm ci --prefix $(HOST)

build:
	npm run build --prefix $(HOST)

lint:
	npm run lint --prefix $(HOST)
	$(STYLUA) --check lua plugin tests
ifdef SELENE
	selene lua plugin tests
else
	@echo "selene not installed; skipping (cargo install selene)"
endif

test:
	npm test --prefix $(HOST)

# Validate the real ~/.pi/agent config boots under the SDK (ADR-003).
# Costs one near-free prompt (thinking off); uses an in-memory session.
smoke:
	npx tsc $(HOST)/scripts/smoke.ts --ignoreConfig --outDir $(HOST)/.smoke --module NodeNext --moduleResolution NodeNext --target ES2023 --skipLibCheck
	node $(HOST)/.smoke/smoke.js
	rm -rf $(HOST)/.smoke

check: lint test build
