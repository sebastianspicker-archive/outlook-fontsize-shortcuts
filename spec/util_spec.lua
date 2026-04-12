require("spec.spec_helper")

local util = require("outlook_font.util")

describe("outlook_font.util", function()
    it("deep_merges nested tables", function()
        local dst = { delays = { activate = 0.1, timeout = 3 } }
        local src = { delays = { timeout = 10 } }

        local merged = util.deep_merge(dst, src)
        assert.equals(0.1, merged.delays.activate)
        assert.equals(10, merged.delays.timeout)
    end)

    it("replaces arrays instead of merging them", function()
        local dst = { appNames = { "Outlook" } }
        local src = { appNames = { "Microsoft Outlook" } }

        local merged = util.deep_merge(dst, src)
        assert.same({ "Microsoft Outlook" }, merged.appNames)
    end)

    it("strips // and /* */ comments but keeps string contents", function()
        local raw = [[
        {
          // line comment
          "a": 1, /* block */ "b": "http://example.com//path"
        }
        ]]

        local stripped = util.strip_jsonc(raw)
        assert.is_truthy(stripped:find([["a": 1]], 1, true))
        assert.is_truthy(stripped:find([["b": "http://example.com//path"]], 1, true))
        assert.is_falsy(stripped:find("// line comment", 1, true))
        assert.is_falsy(stripped:find("/* block */", 1, true))
    end)
end)
