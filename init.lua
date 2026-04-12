-- ~/.hammerspoon/init.lua
--
-- outlook-fontsize-shortcuts
--
-- Copy this file (along with outlook-font.lua and the outlook_font/ directory)
-- into ~/.hammerspoon/ and reload Hammerspoon.
--
-- If you already have an init.lua, merge the sections below into yours.
-- Each section is numbered and independent -- you can reorder or adjust them.

--------------------------------------------------------------------------------
-- 1) Allow hs.application.find() to use Spotlight
--    (Needed so Hammerspoon can locate "Outlook" / "Microsoft Outlook" by name)
--------------------------------------------------------------------------------
hs.application.enableSpotlightForNameSearches(true)

--------------------------------------------------------------------------------
-- 2) Import the Outlook-Font module
--------------------------------------------------------------------------------
local of = require("outlook-font")

--------------------------------------------------------------------------------
-- 3) Notification helper (auto-dismiss after 3 seconds)
--------------------------------------------------------------------------------
local function notify(text)
    local msg = (text ~= nil and tostring(text)) or ""
    hs.notify
        .new({
            title = "Outlook Font",
            informativeText = msg,
            autoWithdraw = true,
            withdrawAfter = 3,
        })
        :send()
end

local function notifyOnSuccess(msg)
    return function(ok)
        if ok then
            notify(msg)
        end
    end
end

--------------------------------------------------------------------------------
-- 4) Load config and bind hotkeys
--    Default shortcuts (override in ~/.hammerspoon/outlook-font.json):
--      Ctrl+Alt+Cmd+G  ->  Increase text size
--      Ctrl+Alt+Cmd+K  ->  Decrease text size
--      Ctrl+Alt+Cmd+T  ->  Toggle (alternates increase/decrease)
--------------------------------------------------------------------------------
of.loadConfig()
local hotkeyMapping = {
    increase = of.cfg.hotkeys.increase,
    decrease = of.cfg.hotkeys.decrease,
    toggle = of.cfg.hotkeys.toggle,
}
hotkeyMapping.onComplete = function(ok, direction)
    if not ok then
        return
    end
    if direction == "increase" then
        notify("Text size increased")
    elseif direction == "decrease" then
        notify("Text size decreased")
    elseif direction == "toggle" then
        notify(of.toggleState and "Text size increased" or "Text size decreased")
    end
end
of.bindHotkeys(hotkeyMapping)

--------------------------------------------------------------------------------
-- 5) Build the menubar dropdown
--    Shortcut hints are shown next to each item for discoverability.
--------------------------------------------------------------------------------
local function shortcutLabel(binding)
    if not binding or not binding.mods or not binding.key then
        return ""
    end
    local symbols = { ctrl = "\u{2303}", alt = "\u{2325}", cmd = "\u{2318}", shift = "\u{21E7}" }
    local parts = {}
    for _, m in ipairs(binding.mods) do
        table.insert(parts, symbols[m] or m)
    end
    table.insert(parts, string.upper(binding.key))
    return "  " .. table.concat(parts)
end

local menuItems = {
    {
        title = "Larger Text Size" .. shortcutLabel(of.cfg.hotkeys.increase),
        fn = function()
            of.adjustTextSize(true, notifyOnSuccess("Text size increased"))
        end,
    },
    {
        title = "Smaller Text Size" .. shortcutLabel(of.cfg.hotkeys.decrease),
        fn = function()
            of.adjustTextSize(false, notifyOnSuccess("Text size decreased"))
        end,
    },
    {
        title = "Toggle Text Size" .. shortcutLabel(of.cfg.hotkeys.toggle),
        fn = function()
            of.toggleTextSize(function(ok)
                if ok then
                    notify(of.toggleState and "Text size increased" or "Text size decreased")
                end
            end)
        end,
    },
    { title = "-" },
    {
        title = "Reload Config",
        fn = function()
            hs.reload()
        end,
    },
}

--------------------------------------------------------------------------------
-- 6) Create the menubar icon (stored globally so it is not garbage-collected)
--------------------------------------------------------------------------------
local menu = hs.menubar.new()
if menu then
    menu:setTitle("A")
    menu:setTooltip("Outlook Font Size Shortcuts")
    menu:setMenu(menuItems)
else
    notify("Could not create menubar item. Check the Hammerspoon console for errors.")
end
