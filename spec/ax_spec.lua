require("spec.spec_helper")

local ax = require("outlook_font.ax")

local function node(attrs)
    local instance = {
        _attrs = attrs or {},
    }

    function instance:attributeValue(key)
        return self._attrs[key]
    end

    return instance
end

describe("outlook_font.ax", function()
    it("finds static text by substring (AXValue)", function()
        local tree = node({
            AXRole = "AXGroup",
            AXChildren = {
                node({ AXRole = "AXStaticText", AXValue = "Text display size" }),
            },
        })

        local found = ax.find_static_text(tree, "display")
        assert.is_not_nil(found)
        assert.equals("AXStaticText", found:attributeValue("AXRole"))
    end)

    it("finds first node by role", function()
        local slider = node({ AXRole = "AXSlider" })
        local tree = node({
            AXRole = "AXGroup",
            AXChildren = {
                node({ AXRole = "AXButton" }),
                node({ AXRole = "AXGroup", AXChildren = { slider } }),
            },
        })

        local found = ax.find_first_by_role(tree, "AXSlider")
        assert.is_not_nil(found)
        assert.equals(slider, found)
    end)

    it("finds a button group near any configured label", function()
        local button1 = node({ AXRole = "AXButton" })
        local button2 = node({ AXRole = "AXButton" })

        local group = node({ AXRole = "AXGroup" })
        local label = node({ AXRole = "AXStaticText", AXValue = "Text display size" })

        label._attrs.AXParent = group
        button1._attrs.AXParent = group
        button2._attrs.AXParent = group
        group._attrs.AXChildren = { label, button1, button2 }

        local tree = node({
            AXRole = "AXWindow",
            AXChildren = { group },
        })
        group._attrs.AXParent = tree

        local buttons = ax.find_button_group_near_labels(tree, { "Text display size" })
        assert.is_not_nil(buttons)
        assert.equals(2, #buttons)
        assert.equals(button1, buttons[1])
        assert.equals(button2, buttons[2])
    end)

    it("finds ancestor by role", function()
        local button = node({ AXRole = "AXButton" })
        local label = node({ AXRole = "AXStaticText", AXValue = "General" })
        label._attrs.AXParent = button

        local found = ax.find_ancestor_by_role(label, "AXButton")
        assert.equals(button, found)
    end)
end)
