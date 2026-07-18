HOST := host
STYLUA := $(shell command -v stylua 2>/dev/null || echo $(HOME)/.local/share/nvim/mason/bin/stylua)
SELENE := $(shell command -v selene 2>/dev/null)

.PHONY: install build lint test check smoke e2e e2e-live

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

NVIM ?= nvim

test:
	npm test --prefix $(HOST)
	$(NVIM) --headless -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/ { minimal_init = 'tests/minimal_init.lua' }"

# Headless full-stack E2E: real host boot in real nvim (no LLM calls).
e2e:
	$(NVIM) --headless -u tests/minimal_init.lua -l tests/e2e.lua

# Validate the real ~/.pi/agent config boots under the SDK (ADR-003).
# Costs one near-free prompt (thinking off); uses an in-memory session.
smoke:
	cd $(HOST) && npx tsc scripts/smoke.ts --ignoreConfig --types node --outDir .smoke --module NodeNext --moduleResolution NodeNext --target ES2023 --skipLibCheck
	node $(HOST)/.smoke/smoke.js
	rm -rf $(HOST)/.smoke

# Live E2E: ONE real prompt through the built host (thinking cycled off).
# Asserts the wire contract the Lua renderer consumes. Costs a few tokens.
e2e-live:
	cd $(HOST) && npx tsc scripts/e2e-live.ts --ignoreConfig --types node --outDir .smoke --module NodeNext --moduleResolution NodeNext --target ES2023 --skipLibCheck
	node $(HOST)/.smoke/e2e-live.js
	rm -rf $(HOST)/.smoke

check: lint test build
