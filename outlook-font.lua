-- ~/.hammerspoon/outlook-font.lua
--[[
outlook-font: Hammerspoon module that changes the "Text display size" of New and
Legacy Outlook for Mac.

This file is the public API (`require("outlook-font")`) and the runtime policy:
config loading, the busy guard, retries, toggle state and user feedback.
Outlook UI automation lives in outlook_font/outlook.lua, configuration in
outlook_font/config.lua, notifications and the overlay in outlook_font/feedback.lua.
--]]

local config = require("outlook_font.config")
local feedback = require("outlook_font.feedback")
local outlook = require("outlook_font.outlook")

local M = {}

-- Public state. `cfg` is replaced by loadConfig(); `toggleState` is the direction
-- of the last successful change (true = larger); set `cfgPath` before loadConfig()
-- to read the config from somewhere other than ~/.hammerspoon/outlook-font.json.
M.cfg = config.defaults()
M.toggleState = false
M.cfgPath = nil

local HS_MODULES = {
    "application",
    "axuielement",
    "canvas",
    "eventtap",
    "hotkey",
    "json",
    "notify",
    "screen",
    "timer",
}

local deps -- hs.* modules, loaded on first use so this file also loads outside Hammerspoon
local fb
local config_loaded = false
local busy = false

local function get_deps()
    if not deps then
        deps = {}
        for _, name in ipairs(HS_MODULES) do
            local ok, mod = pcall(require, "hs." .. name)
            deps[name] = ok and mod or nil
        end
    end
    return deps
end

local function notify(title, message)
    if not fb then
        fb = feedback.new(get_deps())
    end
    fb.notify(title, message)
end

local function show_overlay(isPlus)
    if not M.cfg.showOverlay then
        return
    end
    if not fb then
        fb = feedback.new(get_deps())
    end
    fb.overlay(isPlus and M.cfg.overlayText.larger or M.cfg.overlayText.smaller, M.cfg.overlayDuration)
end

--------------------------------------------------------------------------------
-- Config
--------------------------------------------------------------------------------
-- Loads the config file once; later calls are no-ops (use hs.reload() to re-read).
function M.loadConfig()
    if config_loaded then
        return
    end
    config_loaded = true

    local json = get_deps().json
    local cfg, problems = config.load({
        path = M.cfgPath,
        home = os.getenv("HOME") or "",
        decode = json and json.decode,
    })
    if cfg then
        M.cfg = cfg
    end
    for _, problem in ipairs(problems) do
        notify(problem.title, problem.message)
    end
end

--------------------------------------------------------------------------------
-- Text size changes
--------------------------------------------------------------------------------
-- Runs the synchronous part of adjustTextSize with `busy` already set.
local function start_change(isPlus, callback)
    M.loadConfig()

    local d = get_deps()
    if not (d.timer and d.eventtap) then
        notify(
            "Outlook Font",
            "Required Hammerspoon modules not found. Run this script inside Hammerspoon, not standalone Lua."
        )
        busy = false
        return false
    end

    local app = outlook.find_app(d, M.cfg)
    if not app then
        notify("Outlook Not Found", "Launch Outlook and try again.")
        busy = false
        return false
    end

    if not app:isFrontmost() then
        app:activate()
    end
    if not outlook.ax_app(d, app) then
        notify(
            "Accessibility Required",
            "Grant access in System Settings → Privacy & Security → Accessibility, then restart Hammerspoon."
        )
        busy = false
        return false
    end

    local completed = false
    local function done(ok)
        if completed then
            return
        end
        completed = true
        busy = false
        if type(callback) == "function" then
            callback(ok)
        end
    end

    local function run_attempt(attempt)
        local started, err = pcall(outlook.attempt, d, M.cfg, app, isPlus, function(ok, message, retryable)
            if ok then
                M.toggleState = isPlus
                -- The size already changed; a broken overlay must not turn this into a failure.
                pcall(show_overlay, isPlus)
                done(true)
            elseif retryable and attempt <= M.cfg.retry.attempts then
                d.timer.doAfter(M.cfg.retry.interval, function()
                    run_attempt(attempt + 1)
                end)
            else
                notify("Outlook Font", message)
                done(false)
            end
        end)
        if not started then
            notify("Outlook Font", tostring(err))
            done(false)
        end
    end

    app:activate()
    d.timer.doAfter(M.cfg.delays.activate, function()
        run_attempt(1)
    end)
    return true
end

-- Starts an asynchronous change. Returns false (without calling `callback`) when it
-- cannot start: another change is running, Hammerspoon modules or Outlook are
-- missing, or Accessibility access is not granted. Otherwise returns true and calls
-- `callback(ok)` exactly once when the change finished.
function M.adjustTextSize(isPlus, callback)
    if busy then
        return false
    end
    busy = true

    local ok, started = pcall(start_change, isPlus, callback)
    if not ok then
        -- An unexpected error before the change started must not leave every later
        -- request ignored until Hammerspoon reloads; the error still propagates.
        busy = false
        error(started, 0)
    end
    return started
end

-- Changes the size in the opposite direction of the last successful change.
function M.toggleTextSize(callback)
    return M.adjustTextSize(not M.toggleState, callback)
end

--------------------------------------------------------------------------------
-- Hotkeys
--------------------------------------------------------------------------------
-- mapping = { increase = {mods, key}, decrease = {mods, key}, toggle = {mods, key} | false | nil,
--             onComplete = function(ok, direction) } with direction "increase" | "decrease" | "toggle".
function M.bindHotkeys(mapping)
    local hotkey = get_deps().hotkey
    if not hotkey then
        notify("Outlook Font", "Cannot bind hotkeys. Run this script inside Hammerspoon, not standalone Lua.")
        return
    end

    if type(mapping) ~= "table" then
        notify("Outlook Font", "Hotkey configuration error: mapping must be a table. Check init.lua.")
        return
    end
    local function has_binding(b)
        return type(b) == "table" and type(b.mods) == "table" and b.key ~= nil
    end
    if not has_binding(mapping.increase) or not has_binding(mapping.decrease) then
        notify(
            "Outlook Font",
            "Hotkey configuration error: increase and decrease bindings need .mods and .key. Check init.lua."
        )
        return
    end

    local onComplete = type(mapping.onComplete) == "function" and mapping.onComplete or nil
    local function reporter(direction)
        return function(ok)
            if onComplete then
                onComplete(ok, direction)
            end
        end
    end

    hotkey.bind(mapping.increase.mods, mapping.increase.key, function()
        M.adjustTextSize(true, reporter("increase"))
    end)
    hotkey.bind(mapping.decrease.mods, mapping.decrease.key, function()
        M.adjustTextSize(false, reporter("decrease"))
    end)
    if has_binding(mapping.toggle) then
        hotkey.bind(mapping.toggle.mods, mapping.toggle.key, function()
            M.toggleTextSize(reporter("toggle"))
        end)
    end
end

return M
