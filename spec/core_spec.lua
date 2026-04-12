require("spec.spec_helper")

local of = require("outlook-font")

describe("outlook-font core logic", function()
    before_each(function()
        of._resetForTest()
    end)

    it("returns false when required dependencies are missing", function()
        of._setDeps({})
        local ok = of.adjustTextSize(true)
        assert.is_false(ok)
    end)

    it("returns false when Outlook is not found", function()
        of._setDeps({
            timer = {
                usleep = function() end,
                secondsSinceEpoch = function()
                    return 0
                end,
            },
            eventtap = { keyStroke = function() end },
            application = {
                get = function()
                    return nil
                end,
                find = function()
                    return nil
                end,
            },
        })
        local ok = of.adjustTextSize(true)
        assert.is_false(ok)
    end)

    it("retries menu selection attempts when menus are unavailable", function()
        local select_calls = 0
        local axApp = {
            attributeValue = function()
                return {}
            end,
        }
        local app = {
            activate = function() end,
            isFrontmost = function()
                return true
            end,
            pid = function()
                return 123
            end,
            selectMenuItem = function()
                select_calls = select_calls + 1
                return false
            end,
        }

        of._setDeps({
            timer = {
                usleep = function() end,
                secondsSinceEpoch = function()
                    return 0
                end,
                doAfter = function(_, cb)
                    cb()
                end,
                waitUntil = function(_, cb)
                    cb()
                end,
            },
            eventtap = { keyStroke = function() end },
            application = {
                get = function()
                    return nil
                end,
                find = function()
                    return app
                end,
            },
            axuielement = {
                applicationElement = function()
                    return axApp
                end,
            },
        })

        -- adjustTextSize returns true immediately after starting the async operation
        local ok = of.adjustTextSize(true)
        assert.is_true(ok)
        -- With synchronous mocks, all retries should have been exhausted
        -- 1 initial + 2 retries = 3 attempts * 2 menu options = 6 calls
        assert.equals(6, select_calls)
    end)

    it("uses only the Settings menu in forced new mode", function()
        local attempted_paths = {}
        local app = {
            activate = function() end,
            isFrontmost = function()
                return true
            end,
            pid = function()
                return 123
            end,
            selectMenuItem = function(_, path)
                table.insert(attempted_paths, table.concat(path, " > "))
                return false
            end,
        }

        of._setDeps({
            timer = {
                usleep = function() end,
                secondsSinceEpoch = function()
                    return 0
                end,
                doAfter = function(_, cb)
                    cb()
                end,
                waitUntil = function(_, cb)
                    cb()
                end,
            },
            eventtap = { keyStroke = function() end },
            application = {
                get = function()
                    return nil
                end,
                find = function()
                    return app
                end,
            },
            axuielement = {
                applicationElement = function()
                    return {
                        attributeValue = function()
                            return {}
                        end,
                    }
                end,
            },
        })

        of.cfg.mode = "new"
        local ok = of.adjustTextSize(true)
        assert.is_true(ok)
        assert.same({
            "Outlook > Settings…",
            "Outlook > Settings…",
            "Outlook > Settings…",
        }, attempted_paths)
    end)

    it("uses only the Preferences menu in forced legacy mode", function()
        local attempted_paths = {}
        local app = {
            activate = function() end,
            isFrontmost = function()
                return true
            end,
            pid = function()
                return 123
            end,
            selectMenuItem = function(_, path)
                table.insert(attempted_paths, table.concat(path, " > "))
                return false
            end,
        }

        of._setDeps({
            timer = {
                usleep = function() end,
                secondsSinceEpoch = function()
                    return 0
                end,
                doAfter = function(_, cb)
                    cb()
                end,
                waitUntil = function(_, cb)
                    cb()
                end,
            },
            eventtap = { keyStroke = function() end },
            application = {
                get = function()
                    return nil
                end,
                find = function()
                    return app
                end,
            },
            axuielement = {
                applicationElement = function()
                    return {
                        attributeValue = function()
                            return {}
                        end,
                    }
                end,
            },
        })

        of.cfg.mode = "legacy"
        local ok = of.adjustTextSize(true)
        assert.is_true(ok)
        assert.same({
            "Outlook > Preferences…",
            "Outlook > Preferences…",
            "Outlook > Preferences…",
        }, attempted_paths)
    end)

    it("does not toggle state on failure", function()
        of._setDeps({})
        local ok = of.toggleTextSize()
        assert.is_false(ok)
        assert.is_false(of.toggleState)
    end)
end)
