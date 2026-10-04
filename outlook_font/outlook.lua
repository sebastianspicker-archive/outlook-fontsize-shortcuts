local ax = require("outlook_font.ax")

local M = {}

local BUNDLE_ID = "com.microsoft.Outlook"

local MSG_NO_AX = "Cannot access Outlook UI. Check Accessibility permissions and restart Hammerspoon."
local MSG_MENU_AUTO = "Could not open Settings or Preferences menu. "
    .. "Make sure Outlook is in the foreground and responsive."
local MSG_MENU_NEW = "Could not open the Settings menu in forced new mode. "
    .. "Switch to auto mode if Outlook is still using Preferences."
local MSG_MENU_LEGACY = "Could not open the Preferences menu in forced legacy mode. "
    .. "Switch to auto mode if Outlook is already using Settings."
local MSG_WINDOW_TIMEOUT = "Timed out waiting for the settings window. "
    .. "Try increasing delays.timeout in outlook-font.json."
local MSG_PANE_TIMEOUT = "Timed out waiting for the General pane. "
    .. "Try increasing delays.timeout in outlook-font.json."
local MSG_NO_SLIDER = "Font size slider not found in Preferences. Outlook's UI may have changed."
local MSG_SLIDER_RANGE = "Cannot read slider range. Outlook's UI may have changed."
local MSG_SLIDER_SET = "Could not move the font size slider. Check Accessibility permissions."
local MSG_NO_GENERAL = "'General' tile not found in settings. Outlook's UI may have changed."
local MSG_NO_BUTTONS = "Size buttons not found in settings. Outlook's UI may have changed."
local MSG_BUTTON_PRESS = "Could not click the size button. Outlook's UI may have changed."

function M.find_app(deps, cfg)
    if not deps.application then
        return nil
    end

    -- 1) Try by bundle ID (most robust)
    local app = deps.application.get(BUNDLE_ID)
    if app then
        return app
    end

    -- 2) Fallback to names
    for _, name in ipairs(cfg.appNames or {}) do
        app = deps.application.find(name)
        if app then
            return app
        end
    end
    return nil
end

function M.ax_app(deps, app)
    if not deps.axuielement then
        return nil
    end

    local pid = app and app.pid and app:pid() or nil
    if not pid then
        return nil
    end
    return deps.axuielement.applicationElement(pid)
end

local function get_windows(ax_app)
    if not ax_app then
        return {}
    end
    local ok, value = pcall(function()
        return ax_app:attributeValue("AXWindows")
    end)
    if ok and value then
        return value
    end
    return {}
end

-- Stable identifier for an AX window: AXWindowID, else AXTitle + AXPosition.
local function get_window_id(w)
    local wid = w:attributeValue("AXWindowID")
    if wid then
        return wid
    end
    local title = w:attributeValue("AXTitle") or ""
    local pos = w:attributeValue("AXPosition") or { x = 0, y = 0 }
    return title .. ":" .. tostring(pos.x) .. "," .. tostring(pos.y)
end

-- Returns the valid, visible windows in current_windows that are not in prev_windows.
local function find_new_windows(prev_windows, current_windows)
    local prev = {}
    for _, w in ipairs(prev_windows or {}) do
        local ok, wid = pcall(get_window_id, w)
        if ok then
            prev[wid] = true
        end
    end
    local found = {}
    for _, w in ipairs(current_windows or {}) do
        local ok_id, wid = pcall(get_window_id, w)
        if ok_id and not prev[wid] then
            local ok_attrs, role, hidden = pcall(function()
                return w:attributeValue("AXRole"), w:attributeValue("AXHidden")
            end)
            if ok_attrs and (role == "AXWindow" or role == "AXSheet" or role == "AXDialog") and not hidden then
                local ok_valid = pcall(function()
                    return w:attributeValue("AXTitle") ~= nil or w:attributeValue("AXChildren") ~= nil
                end)
                if ok_valid then
                    table.insert(found, w)
                end
            end
        end
    end
    return found
end

local function has_any_text(win, labels)
    return ax.find_role_or_static_text(win, nil, labels) ~= nil
end

-- True if window looks like Settings/Preferences: slider, personal-settings header, or size label.
-- One tree walk: this also runs over Outlook's (large) main window on every attempt.
local function looks_like_settings(win, cfg)
    if not win then
        return false
    end
    local labels = {}
    for _, list in ipairs({ cfg.headerLabels or {}, cfg.labelTexts or {} }) do
        table.move(list, 1, #list, #labels + 1, labels)
    end
    return ax.find_role_or_static_text(win, "AXSlider", labels) ~= nil
end

-- hs.axuielement's performAction returns the element if the action was accepted,
-- false if it was rejected, and nil + error on an accessibility error.
local function press(elem)
    if not elem then
        return false
    end
    local ok, result = pcall(function()
        return elem:performAction("AXPress")
    end)
    return ok and result ~= nil and result ~= false
end

local function close_window(deps, cfg)
    local ks = cfg.closeWindowKeystroke
    deps.eventtap.keyStroke(ks.mods, ks.key)
end

-- Performs ONE attempt and calls cb(ok, err, retryable) exactly once.
function M.attempt(deps, cfg, app, isPlus, cb)
    local finished = false
    local win = nil
    local mutated = false

    local function finish(ok, err, retryable)
        if finished then
            return
        end
        finished = true
        cb(ok, err, retryable)
    end

    -- Closes the settings window (only once one was found); never throws.
    local function close()
        if win then
            pcall(close_window, deps, cfg)
        end
    end

    local function fail(err, retryable)
        if finished then
            return
        end
        close()
        finish(false, tostring(err), (retryable and not mutated) or false)
    end

    local function succeed()
        if finished then
            return
        end
        close()
        finish(true)
    end

    -- Wraps a callback so any thrown error reaches cb (retryable only before mutation).
    -- Errors raised after cb already ran (i.e. by cb itself) are re-raised so they
    -- surface in the Hammerspoon console instead of vanishing.
    local function guarded(fn)
        return function(...)
            local ok, err = pcall(fn, ...)
            if not ok then
                if finished then
                    error(err, 0)
                end
                fail(err, true)
            end
        end
    end

    -- Polls check() until truthy; calls on_ready(), or on_timeout() once the timeout elapsed.
    local function wait_for(check, on_ready, on_timeout)
        local start_time = deps.timer.secondsSinceEpoch()
        local timed_out = false
        local poll_err = nil
        deps.timer.waitUntil(
            function()
                local ok, result = pcall(function()
                    if deps.timer.secondsSinceEpoch() - start_time > cfg.delays.timeout then
                        timed_out = true
                        return true
                    end
                    return check()
                end)
                if not ok then
                    poll_err = result
                    return true
                end
                return result
            end,
            guarded(function()
                if poll_err ~= nil then
                    error(poll_err, 0)
                end
                if timed_out then
                    on_timeout()
                else
                    on_ready()
                end
            end),
            cfg.delays.waitInterval
        )
    end

    local function legacy_step()
        local slider = ax.find_first_by_role(win, "AXSlider")
        if not slider then
            error(MSG_NO_SLIDER, 0)
        end
        local val = slider:attributeValue("AXValue")
        local minv = slider:attributeValue("AXMinValue")
        local maxv = slider:attributeValue("AXMaxValue")
        if val == nil or minv == nil or maxv == nil then
            error(MSG_SLIDER_RANGE, 0)
        end
        -- Legacy Outlook slider uses integer steps (Standard/Large/Larger)
        local newv = isPlus and math.min(val + 1, maxv) or math.max(val - 1, minv)
        if not slider:setAttributeValue("AXValue", newv) then
            error(MSG_SLIDER_SET, 0)
        end
        mutated = true
        succeed()
    end

    local function press_size_button()
        local buttons = ax.find_button_group_near_labels(win, cfg.labelTexts)
        if not buttons then
            error(MSG_NO_BUTTONS, 0)
        end
        local btn = ax.button_by_size_label(buttons, cfg.overlayText.larger, cfg.overlayText.smaller, isPlus)
        if not btn then
            btn = isPlus and buttons[#buttons] or buttons[1]
        end
        local ok, result = pcall(function()
            return btn:performAction("AXPress")
        end)
        if ok and result == false then
            -- Rejected: the size did not change, so a retry is safe.
            error(MSG_BUTTON_PRESS, 0)
        end
        -- Accepted, or an accessibility error after which the press may still have
        -- landed: never retry from here on.
        mutated = true
        if not ok or result == nil then
            error(MSG_BUTTON_PRESS, 0)
        end
        succeed()
    end

    local function new_outlook_step()
        local pressed = false
        local header
        for _, hl in ipairs(cfg.headerLabels or {}) do
            header = ax.find_static_text(win, hl)
            if header then
                break
            end
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
            pressed = press(general)
        end
        if not pressed then
            for _, label in ipairs(cfg.generalLabels or {}) do
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
        if not pressed and not has_any_text(win, cfg.labelTexts) then
            error(MSG_NO_GENERAL, 0)
        end

        wait_for(
            function()
                return has_any_text(win, cfg.labelTexts)
            end,
            press_size_button,
            function()
                fail(MSG_PANE_TIMEOUT, false)
            end
        )
    end

    local function run_step(legacy)
        if legacy then
            legacy_step()
        else
            new_outlook_step()
        end
    end

    local function try_select_menu(menu_path)
        local ok, selected = pcall(function()
            return app:selectMenuItem(menu_path)
        end)
        return ok and selected == true
    end

    local function body()
        local ax_app = M.ax_app(deps, app)
        if not ax_app then
            fail(MSG_NO_AX, false)
            return
        end

        -- Reuse an already open settings window (ignores cfg.mode)
        local before = get_windows(ax_app)
        for _, w in ipairs(before) do
            if looks_like_settings(w, cfg) then
                win = w
                run_step(ax.find_first_by_role(w, "AXSlider") ~= nil)
                return
            end
        end

        local menu_legacy
        local menu_error = MSG_MENU_AUTO
        if cfg.mode == "new" then
            if try_select_menu(cfg.settingsMenu) then
                menu_legacy = false
            else
                menu_error = MSG_MENU_NEW
            end
        elseif cfg.mode == "legacy" then
            if try_select_menu(cfg.preferencesMenu) then
                menu_legacy = true
            else
                menu_error = MSG_MENU_LEGACY
            end
        elseif try_select_menu(cfg.settingsMenu) then
            menu_legacy = false
        elseif try_select_menu(cfg.preferencesMenu) then
            menu_legacy = true
        end
        if menu_legacy == nil then
            fail(menu_error, true)
            return
        end

        local candidate
        wait_for(function()
            for _, w in ipairs(find_new_windows(before, get_windows(ax_app))) do
                if looks_like_settings(w, cfg) then
                    candidate = w
                    return true
                end
            end
            return false
        end, function()
            win = candidate
            run_step(menu_legacy)
        end, function()
            fail(MSG_WINDOW_TIMEOUT, false)
        end)
    end

    guarded(body)()
end

return M
