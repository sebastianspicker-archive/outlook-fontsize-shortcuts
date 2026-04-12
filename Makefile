LUAROCKS_TREE ?= ./.luarocks
LUAJIT_PREFIX := $(shell brew --prefix luajit 2>/dev/null)

ifeq ($(LUAJIT_PREFIX),)
LUAROCKS := luarocks --tree $(LUAROCKS_TREE)
else
LUAROCKS := luarocks --tree $(LUAROCKS_TREE) --lua-dir $(LUAJIT_PREFIX) --lua-version 5.1
endif

LUACHECK := $(LUAROCKS_TREE)/bin/luacheck
BUSTED := $(LUAROCKS_TREE)/bin/busted

.PHONY: tools lint fmt fmt-check test check clean ci

TOOLS_LUACHECK_VERSION ?= 1.2.0-1
TOOLS_BUSTED_VERSION ?= 2.3.0-1

tools:
	@command -v luarocks >/dev/null || (echo "Missing 'luarocks' (try: brew install luarocks)" && exit 1)
	@mkdir -p $(LUAROCKS_TREE)
	@$(LUAROCKS) install luacheck $(TOOLS_LUACHECK_VERSION)
	@$(LUAROCKS) install busted $(TOOLS_BUSTED_VERSION)

lint: $(LUACHECK)
	@$(LUACHECK) .

fmt:
	@command -v stylua >/dev/null || (echo "Missing 'stylua' (try: brew install stylua)" && exit 1)
	@stylua .

fmt-check:
	@command -v stylua >/dev/null || (echo "Missing 'stylua' (try: brew install stylua)" && exit 1)
	@stylua --check .

test: $(BUSTED)
	@$(BUSTED)

check: fmt-check lint test

ci: fmt-check lint test

clean:
	@echo "Removing $(LUAROCKS_TREE)"
	@$(LUAROCKS) purge --old-versions || true
