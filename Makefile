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

check: lint test build
