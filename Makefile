# Dev tooling for a Hammerspoon (Lua 5.4) project. Tools live in a project-local
# LuaRocks tree; override LUAROCKS to point at a luarocks configured for Lua 5.4.
LUAROCKS_TREE ?= ./.luarocks
LUA_VERSION ?= 5.4
LUAROCKS ?= luarocks
ROCKS := $(LUAROCKS) --tree $(LUAROCKS_TREE) --lua-version $(LUA_VERSION)

LUACHECK := $(LUAROCKS_TREE)/bin/luacheck
BUSTED := $(LUAROCKS_TREE)/bin/busted

TOOLS_LUACHECK_VERSION ?= 1.2.0-1
TOOLS_BUSTED_VERSION ?= 2.3.0-1
# Test-only JSON decoder backing the fake hs.json in spec/support/fake_hs.lua
TOOLS_DKJSON_VERSION ?= 2.11-1

.PHONY: tools lint fmt fmt-check test check clean

tools:
	@command -v $(LUAROCKS) >/dev/null || (echo "Missing '$(LUAROCKS)' (try: brew install luarocks)" && exit 1)
	@mkdir -p $(LUAROCKS_TREE)
	@$(ROCKS) install luacheck $(TOOLS_LUACHECK_VERSION)
	@$(ROCKS) install busted $(TOOLS_BUSTED_VERSION)
	@$(ROCKS) install dkjson $(TOOLS_DKJSON_VERSION)

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

clean:
	@echo "Removing $(LUAROCKS_TREE)"
	@rm -rf $(LUAROCKS_TREE)
