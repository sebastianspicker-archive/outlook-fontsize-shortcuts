-- ~/.hammerspoon/outlook-font.lua
--[[
outlook-font.lua

A Hammerspoon module to control the “Text display size” in both Legacy and New
Outlook for Mac, with:
  • External JSON override (supports JSONC-style comments)
  • Canvas-based visual feedback
  • i18n support (multiple languages)
  • Accessibility health-check
  • Dynamic timeouts & retry logic
  • Toggle-cycle state
--]]

local ax = require("outlook_font.ax")
local util = require("outlook_font.util")

local M = {}

local function safe_require(name)
    local ok, mod = pcall(require, name)
    if ok then
        return mod
    end
    return nil
end

--------------------------------------------------------------------------------
-- 1) Default configuration
--------------------------------------------------------------------------------
local defaultCfg = {
    mode = "auto",
    appNames = { "Outlook", "Microsoft Outlook" },
    settingsMenu = { "Outlook", "Settings…" },
    preferencesMenu = { "Outlook", "Preferences…" },
    headerLabels = {
        "Personal Settings",
        "Persönliche Einstellungen",
        "Paramètres personnels",
        "Configuración personal",
    },
    generalLabels = {
        "General",
        "Allgemein",
        "Général",
    },
    labelTexts = {
        "Text display size",
        "Größe der Textanzeige",
        "Taille d'affichage du texte",
        "Tamaño de visualización de texto",
    },
    overlayText = {
        larger = "Larger",
        smaller = "Smaller",
    },
    closeWindowKeystroke = {
        mods = { "cmd" },
        key = "w",
    },
    delays = {
        activate = 0.1, -- seconds after app:activate()
        waitInterval = 0.05, -- polling interval
        timeout = 3, -- seconds overall timeout for waits
    },
    retry = {
        attempts = 2, -- number of retries after first attempt
        interval = 0.2, -- seconds between retries
    },
    overlayDuration = 1.2, -- seconds before overlay auto-dismisses
    showOverlay = true, -- if false, only notifications are shown (no canvas)
    hotkeys = {
        increase = { mods = { "ctrl", "alt", "cmd" }, key = "g" },
        decrease = { mods = { "ctrl", "alt", "cmd" }, key = "k" },
        toggle = { mods = { "ctrl", "alt", "cmd" }, key = "t" },
    },
}

M.cfg = util.deep_copy(defaultCfg)

-- Single overlay instance for debounce (reuse one canvas, reset timer on rapid calls)
local overlay_canvas_ref = nil
local overlay_timer_ref = nil
local busy = false
M.toggleState = false

--------------------------------------------------------------------------------
-- 2) Dependency and notification helpers
--------------------------------------------------------------------------------
M._deps = nil

function M._setDeps(deps)
    M._deps = deps
end

local function get_deps()
    if M._deps then
        return M._deps
    end

    M._deps = {
        application = safe_require("hs.application"),
        axuielement = safe_require("hs.axuielement"),
        canvas = safe_require("hs.canvas"),
        eventtap = safe_require("hs.eventtap"),
        hotkey = safe_require("hs.hotkey"),
        notify = safe_require("hs.notify"),
        screen = safe_require("hs.screen"),
        timer = safe_require("hs.timer"),
    }

    return M._deps
end

local function notify(title, message)
    local t = (title ~= nil and tostring(title)) or ""
    local m = (message ~= nil and tostring(message)) or ""
    local deps = get_deps()
    if deps.notify and deps.notify.new then
        deps.notify
            .new({
                title = t,
                informativeText = m,
                autoWithdraw = true,
                withdrawAfter = 3,
            })
            :send()
        return
    end

    if io and io.stderr then
        io.stderr:write(string.format("%s: %s\n", t, m))
    end
end

--------------------------------------------------------------------------------
-- 2.5) Config validation (defensive against invalid override types)
--------------------------------------------------------------------------------
local function is_string_array(value)
    if type(value) ~= "table" then
        return false
    end
    if #value < 1 then
        return false
    end
    for i = 1, #value do
        if type(value[i]) ~= "string" then
            return false
        end
    end
    for k in pairs(value) do
        if type(k) ~= "number" or k < 1 or k > #value then
            return false
        end
    end
    return true
end

local function sanitize_config(ext)
    if type(ext) ~= "table" then
        return util.deep_copy(defaultCfg)
    end

    local merged = util.deep_merge(util.deep_copy(defaultCfg), ext)
    local warnings = {}

    local function warn(key, expected)
        table.insert(warnings, key .. " (" .. expected .. ")")
    end

    local function reset_top(key)
        merged[key] = util.deep_copy(defaultCfg[key])
    end

    if merged.mode ~= nil and merged.mode ~= "auto" and merged.mode ~= "new" and merged.mode ~= "legacy" then
        warn("mode", '"auto" | "new" | "legacy"')
        merged.mode = defaultCfg.mode
    end

    local function ensure_string_array(key)
        if merged[key] ~= nil and not is_string_array(merged[key]) then
            warn(key, "string[]")
            reset_top(key)
        end
    end

    local function ensure_table_with_fields(key, fields)
        if merged[key] == nil then
            return
        end
        if type(merged[key]) ~= "table" then
            warn(key, "table")
            reset_top(key)
            return
        end
        for subkey, expected in pairs(fields) do
            local value = merged[key][subkey]
            if value ~= nil and type(value) ~= expected then
                warn(key .. "." .. subkey, expected)
                merged[key][subkey] = defaultCfg[key][subkey]
            end
        end
    end

    ensure_string_array("appNames")
    ensure_string_array("settingsMenu")
    ensure_string_array("preferencesMenu")
    ensure_string_array("headerLabels")
    ensure_string_array("generalLabels")
    ensure_string_array("labelTexts")

    ensure_table_with_fields("overlayText", { larger = "string", smaller = "string" })
    ensure_table_with_fields("closeWindowKeystroke", { mods = "table", key = "string" })
    -- closeWindowKeystroke.mods must be array of strings (for eventtap.keyStroke)
    if merged.closeWindowKeystroke and not is_string_array(merged.closeWindowKeystroke.mods) then
        warn("closeWindowKeystroke.mods", "string[]")
        merged.closeWindowKeystroke.mods = util.deep_copy(defaultCfg.closeWindowKeystroke.mods)
    end
    ensure_table_with_fields("delays", { activate = "number", waitInterval = "number", timeout = "number" })
    ensure_table_with_fields("retry", { attempts = "number", interval = "number" })

    if merged.overlayDuration ~= nil and type(merged.overlayDuration) ~= "number" then
        warn("overlayDuration", "number")
        merged.overlayDuration = defaultCfg.overlayDuration
    end
    if merged.showOverlay ~= nil and type(merged.showOverlay) ~= "boolean" then
        warn("showOverlay", "boolean")
        merged.showOverlay = defaultCfg.showOverlay
    end

    local function valid_binding(b)
        return type(b) == "table" and is_string_array(b.mods) and type(b.key) == "string"
    end
    if
        merged.hotkeys == nil
        or type(merged.hotkeys) ~= "table"
        or not valid_binding(merged.hotkeys.increase)
        or not valid_binding(merged.hotkeys.decrease)
    then
        if merged.hotkeys ~= nil then
            warn("hotkeys", "table with .increase/.decrease { mods, key }")
        end
        merged.hotkeys = util.deep_copy(defaultCfg.hotkeys)
    elseif
        merged.hotkeys.toggle ~= nil
        and merged.hotkeys.toggle ~= false
        and not valid_binding(merged.hotkeys.toggle)
    then
        merged.hotkeys.toggle = util.deep_copy(defaultCfg.hotkeys.toggle)
    end

    if #warnings > 0 then
        notify("Config Warning", "Invalid config keys reset to defaults: " .. table.concat(warnings, ", "))
    end

    return merged
end

function M._sanitizeConfig(ext)
    return sanitize_config(ext)
end

-- Shows a brief overlay; debounced (single canvas, timer reset on rapid calls).
local function showOverlay(text)
    if not M.cfg.showOverlay then
        return
    end
    if type(text) ~= "string" then
        text = ""
    end
    local deps = get_deps()
    if not (deps.canvas and deps.screen and deps.timer) then
        return
    end

    -- Debounce: cancel previous timer and remove previous canvas
    if overlay_timer_ref then
        pcall(function()
            overlay_timer_ref:stop()
        end)
        overlay_timer_ref = nil
    end
    if overlay_canvas_ref then
        pcall(function()
            overlay_canvas_ref:hide()
        end)
        pcall(function()
            overlay_canvas_ref:delete()
        end)
        overlay_canvas_ref = nil
    end

    local main = deps.screen.mainScreen()
    if not main then
        return
    end
    local screen = main:fullFrame()
    local width, height = math.min(300, screen.w * 0.5), 60
    local x = screen.x + (screen.w - width) / 2
    local y = screen.y + (screen.h - height) / 2

    local c = deps.canvas.new({ x = x, y = y, w = width, h = height })
    if not c then
        return
    end

    overlay_canvas_ref = c
    c[1] = {
        type = "rectangle",
        action = "fill",
        frame = { x = 0, y = 0, w = 1, h = 1 },
        fillColor = { white = 0.1, alpha = 0.8 },
        roundedRectRadii = { xRadius = 12, yRadius = 12 },
        strokeColor = { white = 1, alpha = 0.9 },
        strokeWidth = 2,
    }
    c[2] = {
        type = "text",
        text = text,
        frame = { x = 0, y = 0, w = 1, h = 1 },
        textColor = { white = 1 },
        textSize = 28,
        textFont = "Helvetica Bold",
        alignment = "center",
    }
    c:show()

    local duration = (type(M.cfg.overlayDuration) == "number" and M.cfg.overlayDuration > 0) and M.cfg.overlayDuration
        or 1.2
    overlay_timer_ref = deps.timer.doAfter(duration, function()
        if overlay_canvas_ref then
            pcall(function()
                overlay_canvas_ref:hide()
            end)
            pcall(function()
                overlay_canvas_ref:delete()
            end)
            overlay_canvas_ref = nil
        end
        overlay_timer_ref = nil
    end)
end

--------------------------------------------------------------------------------
-- 3) Config loading (supports JSONC comments)
--------------------------------------------------------------------------------
local config_loaded = false

function M._resetForTest()
    M.cfg = util.deep_copy(defaultCfg)
    M.toggleState = false
    M._deps = nil
    config_loaded = false
    busy = false
    if overlay_timer_ref then
        pcall(function()
            overlay_timer_ref:stop()
        end)
        overlay_timer_ref = nil
    end
    if overlay_canvas_ref then
        pcall(function()
            overlay_canvas_ref:hide()
        end)
        pcall(function()
            overlay_canvas_ref:delete()
        end)
        overlay_canvas_ref = nil
    end
end

local function decode_json(raw)
    if type(raw) ~= "string" then
        return nil, "invalid input"
    end
    local hs_json = safe_require("hs.json")
    if hs_json and hs_json.decode then
        local ok, value = pcall(function()
            return hs_json.decode(raw)
        end)
        if ok then
            return value, nil
        end
        return nil, "hs.json.decode failed"
    end

    local dkjson = safe_require("dkjson")
    if dkjson and dkjson.decode then
        local ok, value, _, err = pcall(function()
            return dkjson.decode(raw)
        end)
        if not ok then
            return nil, "dkjson.decode failed"
        end
        if err then
            return nil, err
        end
        return value, nil
    end

    return nil, "no JSON decoder available"
end

local function ensure_config_loaded()
    if config_loaded then
        return
    end
    config_loaded = true

    local home = os.getenv("HOME") or ""
    local cfgPath = M.cfgPath or (home .. "/.hammerspoon/outlook-font.json")

    -- Reject path traversal in any path
    if cfgPath:match("%.%.") then
        notify("Config Error", "Invalid config path: path traversal not allowed")
        return
    end

    -- Expand leading ~ to HOME (io.open does not expand ~)
    if cfgPath:sub(1, 1) == "~" then
        local rest = (cfgPath:sub(2, 2) == "/" or cfgPath:sub(2, 2) == "") and cfgPath:sub(2) or "/" .. cfgPath:sub(2)
        cfgPath = home .. rest
    end

    -- When using custom M.cfgPath, require absolute or ~ path
    if M.cfgPath and cfgPath:sub(1, 1) ~= "/" and home == "" then
        notify("Config Error", "Config path must be absolute or use ~; HOME is not set")
        return
    end

    -- Avoid reading from root if HOME is unset and default path was used
    if not M.cfgPath and home == "" then
        notify("Config Warning", "HOME is not set; skipping config file load")
        return
    end

    local f = io.open(cfgPath, "r")
    if not f then
        return
    end
    local ok_read, raw = pcall(function()
        return f:read("*a")
    end)
    f:close()
    if not ok_read or raw == nil then
        if not ok_read then
            notify("Config Error", string.format("Failed to read %s (%s)", cfgPath, tostring(raw)))
        end
        return
    end

    local ext, decode_err = decode_json(util.strip_jsonc(raw))
    if type(ext) == "table" then
        M.cfg = sanitize_config(ext)
    elseif ext ~= nil then
        notify("Config Error", string.format("Expected object in %s", cfgPath))
    elseif decode_err then
        notify("Config Error", string.format("Failed to parse %s (%s)", cfgPath, decode_err))
    end
end

function M.loadConfig()
    ensure_config_loaded()
end

local function resolve_requested_mode(cfg)
    if cfg and (cfg.mode == "new" or cfg.mode == "legacy") then
        return cfg.mode
    end
    return "auto"
end

--------------------------------------------------------------------------------
-- 4) Outlook discovery and accessibility health-check
--------------------------------------------------------------------------------
local function getOutlookApp()
    local deps = get_deps()
    if not deps.application then
        return nil
    end

    -- 1) Try by bundle ID (most robust)
    local app = deps.application.get("com.microsoft.Outlook")
    if app then
        return app
    end

    -- 2) Fallback to names
    for _, name in ipairs(M.cfg.appNames) do
        app = deps.application.find(name)
        if app then
            return app
        end
    end
    return nil
end

local function get_ax_app(app)
    local deps = get_deps()
    if not deps.axuielement then
        return nil
    end

    local pid = app and app.pid and app:pid() or nil
    if not pid then
        return nil
    end
    return deps.axuielement.applicationElement(pid)
end

local function healthCheck(app)
    if not app then
        return false
    end

    if not app:isFrontmost() then
        app:activate()
    end

    local axApp = get_ax_app(app)
    if not axApp then
        notify(
            "Accessibility Required",
            "Grant access in System Settings → Privacy & Security → Accessibility, then restart Hammerspoon."
        )
        return false
    end

    return true
end

--------------------------------------------------------------------------------
-- 5) Wait helpers
--------------------------------------------------------------------------------
local function get_windows(axApp)
    if not axApp then
        return {}
    end
    local ok, value = pcall(function()
        return axApp:attributeValue("AXWindows")
    end)
    if ok and value then
        return value
    end
    return {}
end

-- Returns a stable identifier for an AX window. Uses AXWindowID when available,
-- falls back to a composite of AXTitle + AXPosition, and finally object identity.
local function get_window_id(w)
    local wid = w:attributeValue("AXWindowID")
    if wid then
        return wid
    end
    local title = w:attributeValue("AXTitle") or ""
    local pos = w:attributeValue("AXPosition") or { x = 0, y = 0 }
    return title .. ":" .. tostring(pos.x) .. "," .. tostring(pos.y)
end

-- Uses a single snapshot (current_windows) to avoid race; prev/current keyed by object identity.
-- Verifies the found window is valid and visible.
-- Uses pcall for safety in case window objects become invalid during comparison.
local function find_new_window_from_lists(prev_windows, current_windows)
    local prev = {}
    for _, w in ipairs(prev_windows or {}) do
        -- Use get_window_id for stable deduplication even without AXWindowID
        local ok, wid = pcall(function()
            return get_window_id(w)
        end)
        if ok then
            prev[wid] = true
        end
    end
    for _, w in ipairs(current_windows or {}) do
        -- Get identifier for comparison
        local ok_id, wid = pcall(function()
            return get_window_id(w)
        end)
        if ok_id and not prev[wid] then
            -- Additional safety: ensure it's a standard window or dialog and visible
            -- Use pcall to handle potentially invalid window objects
            local ok_attrs, role, hidden = pcall(function()
                return w:attributeValue("AXRole"), w:attributeValue("AXHidden")
            end)
            if ok_attrs and (role == "AXWindow" or role == "AXSheet" or role == "AXDialog") and not hidden then
                -- Final validation: try to get the window's title to ensure it's still valid
                local ok_valid = pcall(function()
                    return w:attributeValue("AXTitle") ~= nil or w:attributeValue("AXChildren") ~= nil
                end)
                if ok_valid then
                    return w
                end
            end
        end
    end
    return nil
end

-- True if window looks like Settings/Preferences (has slider or personal-settings header).
local function is_likely_settings_window(win)
    if not win then
        return false
    end
    if ax.find_first_by_role(win, "AXSlider") then
        return true
    end
    for _, hl in ipairs(M.cfg.headerLabels) do
        if ax.find_static_text(win, hl) then
            return true
        end
    end
    return false
end

-- Helper to close window using configurable keystroke
local function close_window(deps)
    local ks = M.cfg.closeWindowKeystroke or { mods = { "cmd" }, key = "w" }
    deps.eventtap.keyStroke(ks.mods, ks.key)
end

--------------------------------------------------------------------------------
-- 6) Core function: adjust text size with retry logic
-- Optional second argument: callback(ok) invoked once when the attempt finishes.
--------------------------------------------------------------------------------
function M.adjustTextSize(isPlus, callback)
    if busy then
        return false
    end
    busy = true

    ensure_config_loaded()

    local deps = get_deps()
    if not (deps.timer and deps.eventtap) then
        notify(
            "Outlook Font",
            "Required Hammerspoon modules not found. Run this script inside Hammerspoon, not standalone Lua."
        )
        busy = false
        return false
    end

    local app = getOutlookApp()
    if not app then
        notify("Outlook Not Found", "Launch Outlook and try again.")
        busy = false
        return false
    end
    if not healthCheck(app) then
        busy = false
        return false
    end

    local completion_cb = (type(callback) == "function") and callback or nil
    local completed = false
    local function done(ok)
        if completed then
            return
        end
        completed = true
        busy = false
        if completion_cb then
            completion_cb(ok)
        end
    end

    local function run_attempt(attempt)
        local attempt_ok, _ = pcall(function()
            local axApp = get_ax_app(app)
            if not axApp then
                notify(
                    "Outlook Font",
                    "Cannot access Outlook UI. Check Accessibility permissions and restart Hammerspoon."
                )
                done(false)
                return
            end

            -- BUG 9: Check for pre-open settings window before taking snapshot
            local existing_windows = get_windows(axApp)
            local existing_settings_win = nil
            for _, w in ipairs(existing_windows) do
                if is_likely_settings_window(w) then
                    existing_settings_win = w
                    break
                end
            end

            if existing_settings_win then
                -- Settings window already open; use it directly (skip menu trigger and waitUntil)
                local win = existing_settings_win
                local timeout = M.cfg.delays.timeout or 3

                local ok, err = pcall(function()
                    if ax.find_first_by_role(win, "AXSlider") then
                        -- Legacy mode
                        local slider = ax.find_first_by_role(win, "AXSlider")
                        local val = slider:attributeValue("AXValue")
                        local minv = slider:attributeValue("AXMinValue")
                        local maxv = slider:attributeValue("AXMaxValue")
                        if val == nil or minv == nil or maxv == nil then
                            error("Cannot read slider range. Outlook's UI may have changed.")
                        end
                        local newv = isPlus and math.min(val + 1, maxv) or math.max(val - 1, minv)
                        if not slider:setAttributeValue("AXValue", newv) then
                            error("Could not move the font size slider. Check Accessibility permissions.")
                        end
                        close_window(deps)
                        M.toggleState = isPlus
                        showOverlay(isPlus and M.cfg.overlayText.larger or M.cfg.overlayText.smaller)
                        done(true)
                    else
                        -- New Outlook mode: find header and navigate to General pane
                        local header
                        for _, hl in ipairs(M.cfg.headerLabels) do
                            header = ax.find_static_text(win, hl)
                            if header then
                                break
                            end
                        end

                        local function press(elem)
                            if not elem then
                                return false
                            end
                            local ok_press, result = pcall(function()
                                return elem:performAction("AXPress")
                            end)
                            return ok_press and result == true
                        end

                        if header then
                            local parent = header:attributeValue("AXParent")
                            local siblings = parent and parent:attributeValue("AXChildren") or {}
                            local header_idx
                            for i, v in ipairs(siblings) do
                                if v == header then
                                    header_idx = i
                                    break
                                end
                            end
                            local general = header_idx and header_idx > 1 and siblings[header_idx - 1] or nil
                            local pressed = press(general)
                            if not pressed then
                                for _, label in ipairs(M.cfg.generalLabels) do
                                    local label_node = ax.find_static_text(win, label)
                                    if label_node then
                                        local btn = ax.find_ancestor_by_role(label_node, "AXButton") or label_node
                                        if press(btn) then
                                            pressed = true
                                            break
                                        end
                                    end
                                end
                            end
                            if not pressed then
                                error("'General' tile not found in settings. Outlook's UI may have changed.")
                            end
                        end

                        -- Wait for labels in the General pane
                        local label_start_time = deps.timer.secondsSinceEpoch()
                        local label_timed_out = false

                        deps.timer.waitUntil(function()
                            if deps.timer.secondsSinceEpoch() - label_start_time > timeout then
                                label_timed_out = true
                                return true
                            end
                            for _, label in ipairs(M.cfg.labelTexts) do
                                if ax.find_static_text(win, label) then
                                    return true
                                end
                            end
                            return false
                        end, function()
                            if label_timed_out then
                                close_window(deps)
                                notify(
                                    "Outlook Font",
                                    "Timed out waiting for the General pane. "
                                        .. "Try increasing delays.timeout in outlook-font.json."
                                )
                                done(false)
                                return
                            end
                            local ok2, err2 = pcall(function()
                                local buttons = ax.find_button_group_near_labels(win, M.cfg.labelTexts)
                                if not buttons then
                                    error("Size buttons not found in settings. Outlook's UI may have changed.")
                                end
                                local larger_text, smaller_text = M.cfg.overlayText.larger, M.cfg.overlayText.smaller
                                local btn = ax.button_by_size_label(buttons, larger_text, smaller_text, isPlus)
                                if not btn then
                                    btn = isPlus and buttons[#buttons] or buttons[1]
                                end
                                if btn:performAction("AXPress") == false then
                                    error("Could not click the size button. Outlook's UI may have changed.")
                                end
                                close_window(deps)
                                M.toggleState = isPlus
                                showOverlay(isPlus and M.cfg.overlayText.larger or M.cfg.overlayText.smaller)
                                done(true)
                            end)
                            if not ok2 then
                                close_window(deps)
                                notify("Outlook Font", tostring(err2))
                                done(false)
                            end
                        end, M.cfg.delays.waitInterval)
                    end
                end)

                if not ok then
                    close_window(deps)
                    notify("Outlook Font", tostring(err))
                    done(false)
                end
                return
            end

            local before = get_windows(axApp)

            local function try_select_menu(menu_path)
                local ok_select, selected = pcall(function()
                    return app:selectMenuItem(menu_path)
                end)
                return ok_select and selected == true
            end

            local requestedMode = resolve_requested_mode(M.cfg)
            local modeLegacy
            local menuOpened = false
            local menuError = "Could not open Settings or Preferences menu. "
                .. "Make sure Outlook is in the foreground and responsive."

            if requestedMode == "new" then
                if try_select_menu(M.cfg.settingsMenu) then
                    modeLegacy = false
                    menuOpened = true
                else
                    menuError = "Could not open the Settings menu in forced new mode. "
                        .. "Switch to auto mode if Outlook is still using Preferences."
                end
            elseif requestedMode == "legacy" then
                if try_select_menu(M.cfg.preferencesMenu) then
                    modeLegacy = true
                    menuOpened = true
                else
                    menuError = "Could not open the Preferences menu in forced legacy mode. "
                        .. "Switch to auto mode if Outlook is already using Settings."
                end
            elseif try_select_menu(M.cfg.settingsMenu) then
                modeLegacy = false
                menuOpened = true
            elseif try_select_menu(M.cfg.preferencesMenu) then
                modeLegacy = true
                menuOpened = true
            end

            if not menuOpened then
                if attempt <= (M.cfg.retry.attempts or 1) then
                    deps.timer.doAfter(M.cfg.retry.interval or 0.2, function()
                        run_attempt(attempt + 1)
                    end)
                else
                    notify("Outlook Font", menuError)
                    done(false)
                end
                return
            end

            -- Step 2: Wait for window with timeout
            local win
            local start_time = deps.timer.secondsSinceEpoch()
            local timeout = M.cfg.delays.timeout or 3
            local timed_out = false

            deps.timer.waitUntil(function()
                if deps.timer.secondsSinceEpoch() - start_time > timeout then
                    timed_out = true
                    return true -- Exit the wait
                end
                local current = get_windows(axApp)
                win = find_new_window_from_lists(before, current)
                if win and not is_likely_settings_window(win) then
                    win = nil
                end
                return win ~= nil
            end, function()
                if timed_out then
                    notify(
                        "Outlook Font",
                        "Timed out waiting for the settings window. Try increasing delays.timeout in outlook-font.json."
                    )
                    done(false)
                    return
                end
                -- Step 3: Interaction
                local ok, err = pcall(function()
                    if modeLegacy then
                        local slider = ax.find_first_by_role(win, "AXSlider")
                        if not slider then
                            error("Font size slider not found in Preferences. Outlook's UI may have changed.")
                        end
                        local val = slider:attributeValue("AXValue")
                        local minv = slider:attributeValue("AXMinValue")
                        local maxv = slider:attributeValue("AXMaxValue")
                        if val == nil or minv == nil or maxv == nil then
                            error("Cannot read slider range. Outlook's UI may have changed.")
                        end
                        -- Legacy Outlook slider uses integer steps (Standard/Large/Larger)
                        local newv = isPlus and math.min(val + 1, maxv) or math.max(val - 1, minv)
                        if not slider:setAttributeValue("AXValue", newv) then
                            error("Could not move the font size slider. Check Accessibility permissions.")
                        end
                    else
                        local header
                        for _, hl in ipairs(M.cfg.headerLabels) do
                            header = ax.find_static_text(win, hl)
                            if header then
                                break
                            end
                        end
                        if not header then
                            error("Settings header not found. Outlook's UI may have changed.")
                        end

                        local parent = header:attributeValue("AXParent")
                        local siblings = parent and parent:attributeValue("AXChildren") or {}
                        local header_idx
                        for i, v in ipairs(siblings) do
                            if v == header then
                                header_idx = i
                                break
                            end
                        end

                        local function press(elem)
                            if not elem then
                                return false
                            end
                            local ok_press, result = pcall(function()
                                return elem:performAction("AXPress")
                            end)
                            return ok_press and result == true
                        end

                        local general = header_idx and header_idx > 1 and siblings[header_idx - 1] or nil
                        local pressed = press(general)

                        if not pressed then
                            for _, label in ipairs(M.cfg.generalLabels) do
                                local label_node = ax.find_static_text(win, label)
                                if label_node then
                                    local btn = ax.find_ancestor_by_role(label_node, "AXButton") or label_node
                                    if press(btn) then
                                        pressed = true
                                        break
                                    end
                                end
                            end
                        end

                        if not pressed then
                            error("'General' tile not found in settings. Outlook's UI may have changed.")
                        end

                        -- Sub-step: Wait for labels in the "General" pane with timeout
                        local label_start_time = deps.timer.secondsSinceEpoch()
                        local label_timed_out = false

                        deps.timer.waitUntil(function()
                            if deps.timer.secondsSinceEpoch() - label_start_time > timeout then
                                label_timed_out = true
                                return true
                            end
                            for _, label in ipairs(M.cfg.labelTexts) do
                                if ax.find_static_text(win, label) then
                                    return true
                                end
                            end
                            return false
                        end, function()
                            if label_timed_out then
                                close_window(deps)
                                notify(
                                    "Outlook Font",
                                    "Timed out waiting for the General pane. "
                                        .. "Try increasing delays.timeout in outlook-font.json."
                                )
                                done(false)
                                return
                            end
                            local ok2, err2 = pcall(function()
                                local buttons = ax.find_button_group_near_labels(win, M.cfg.labelTexts)
                                if not buttons then
                                    error("Size buttons not found in settings. Outlook's UI may have changed.")
                                end
                                local larger_text, smaller_text = M.cfg.overlayText.larger, M.cfg.overlayText.smaller
                                local btn = ax.button_by_size_label(buttons, larger_text, smaller_text, isPlus)
                                if not btn then
                                    btn = isPlus and buttons[#buttons] or buttons[1]
                                end
                                if btn:performAction("AXPress") == false then
                                    error("Could not click the size button. Outlook's UI may have changed.")
                                end

                                close_window(deps)
                                M.toggleState = isPlus
                                showOverlay(isPlus and M.cfg.overlayText.larger or M.cfg.overlayText.smaller)
                                done(true)
                            end)
                            if not ok2 then
                                close_window(deps)
                                notify("Outlook Font", tostring(err2))
                                done(false)
                            end
                        end, M.cfg.delays.waitInterval)
                        return -- Exit pcall flow, let waitUntil handle the rest
                    end

                    close_window(deps)
                    M.toggleState = isPlus
                    showOverlay(isPlus and M.cfg.overlayText.larger or M.cfg.overlayText.smaller)
                    done(true)
                end)

                if not ok and err then
                    close_window(deps)
                    if attempt <= (M.cfg.retry.attempts or 1) then
                        deps.timer.doAfter(M.cfg.retry.interval or 0.2, function()
                            run_attempt(attempt + 1)
                        end)
                    else
                        notify("Outlook Font", tostring(err))
                        done(false)
                    end
                end
            end, M.cfg.delays.waitInterval)
        end)
        if not attempt_ok then
            done(false)
        end
    end

    app:activate()
    deps.timer.doAfter(M.cfg.delays.activate or 0.1, function()
        run_attempt(1)
    end)

    return true
end

--------------------------------------------------------------------------------
-- 7) Toggle helper (only updates state on success). Optional callback(ok).
--------------------------------------------------------------------------------
function M.toggleTextSize(callback)
    local next_state = not M.toggleState
    return M.adjustTextSize(next_state, callback)
end

--------------------------------------------------------------------------------
-- 8) Hotkey binding including toggle
-- Optional mapping.onComplete(ok, direction) with direction "increase"|"decrease"|"toggle".
--------------------------------------------------------------------------------
function M.bindHotkeys(mapping)
    local deps = get_deps()
    if not deps.hotkey then
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

    deps.hotkey.bind(mapping.increase.mods, mapping.increase.key, function()
        M.adjustTextSize(true, function(ok)
            if onComplete then
                onComplete(ok, "increase")
            end
        end)
    end)
    deps.hotkey.bind(mapping.decrease.mods, mapping.decrease.key, function()
        M.adjustTextSize(false, function(ok)
            if onComplete then
                onComplete(ok, "decrease")
            end
        end)
    end)
    if mapping.toggle then
        if has_binding(mapping.toggle) then
            deps.hotkey.bind(mapping.toggle.mods, mapping.toggle.key, function()
                M.toggleTextSize(function(ok)
                    if onComplete then
                        onComplete(ok, "toggle")
                    end
                end)
            end)
        end
    end
end

return M
