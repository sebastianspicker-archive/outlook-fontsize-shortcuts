require("spec.spec_helper")

describe("outlook-font module", function()
    it("loads outside Hammerspoon (no hs.* modules)", function()
        package.loaded["outlook-font"] = nil
        assert.has_no.errors(function()
            require("outlook-font")
        end)
    end)
end)
