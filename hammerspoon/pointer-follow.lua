-- Hammerspoon wiring for pointer.lua: when focus moves by keyboard, the pointer
-- follows. The decisions live in pointer.lua; this only feeds it events and
-- performs the move. See docs/superpowers/specs/2026-10-25-pointer-follows-focus-design.md.
local here = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") or "."
local pointer = dofile(here .. "/pointer.lua")

local M = {}

local types = hs.eventtap.event.types

-- opts.debug: print each decision to the Hammerspoon console.
-- opts.window: seconds after a key event that a focus change still counts (default 0.5).
-- opts.postMoveEvent: also post a mouse-moved event after the move, so hover states update.
function M.start(opts)
    opts = opts or {}
    local function log(...) if opts.debug then print("[pointer-follow]", ...) end end

    local evidence = pointer.newEvidence(opts.window)
    local spots = {}          -- window id -> offset from the window's top-left
    -- The window that currently has focus. Seed it now, so the first switch after a
    -- (re)load can still remember where the pointer was in the window being left.
    local current = hs.window.focusedWindow()
    if current and not (current:id() and current:isStandard()) then current = nil end
    local ownMoveAt = -1      -- when we last moved the pointer ourselves

    -- nil when the window has gone away between the event and now.
    local function frameOf(w)
        local ok, f = pcall(w.frame, w)
        if not ok or not f then return nil end
        return {x = f.x, y = f.y, w = f.w, h = f.h}
    end

    local function orderedItems()
        local items = {}
        for _, w in ipairs(hs.window.orderedWindows()) do
            local id = w:id()
            local frame = id and w:isStandard() and frameOf(w)
            if frame then items[#items + 1] = {id = id, frame = frame} end
        end
        return items
    end

    local function screenFrames()
        local list = {}
        for _, s in ipairs(hs.screen.allScreens()) do
            local f = s:fullFrame() -- spots over the menu bar or Dock are still on screen
            list[#list + 1] = {x = f.x, y = f.y, w = f.w, h = f.h}
        end
        return list
    end

    -- Every key press counts, including plain typing: switchers like Contexts are
    -- driven with unmodified keys (type a search, press Enter). A modifier change
    -- counts only for cmd, ctrl and alt, so shift while typing is not noise.
    local function significant(flags) return flags.cmd or flags.ctrl or flags.alt end
    local wasSignificant = false

    M.tap = hs.eventtap.new({
        types.keyDown, types.flagsChanged, types.leftMouseDown, types.rightMouseDown,
        types.otherMouseDown, types.scrollWheel, types.mouseMoved,
    }, function(e)
        local now = hs.timer.secondsSinceEpoch()
        local t = e:getType()
        if t == types.keyDown then
            pointer.noteKey(evidence, now)
        elseif t == types.flagsChanged then
            local sig = significant(e:getFlags())
            -- Pressing or releasing a significant modifier counts; shift alone does not.
            if sig then pointer.noteKey(evidence, now)
            elseif wasSignificant then pointer.noteRelease(evidence, now) end
            wasSignificant = sig
            pointer.noteModifiers(evidence, sig and true or false)
        elseif t == types.leftMouseDown or t == types.rightMouseDown or t == types.otherMouseDown then
            local p = e:location()
            pointer.noteClick(evidence, now, {x = p.x, y = p.y})
        elseif t ~= types.mouseMoved or now - ownMoveAt > 0.1 then
            pointer.noteMouse(evidence, now)
        end
        return false
    end)
    M.tap:start()

    -- macOS can disable an event tap (timeout, secure input). Restart it, and
    -- forget what we saw: events may have been missed in the meantime.
    M.watchdog = hs.timer.doEvery(5, function()
        if not M.tap:isEnabled() then
            log("event tap was disabled; restarting")
            pointer.reset(evidence)
            wasSignificant = false
            M.tap:start()
        end
    end)

    M.filter = hs.window.filter.new()
    M.filter:subscribe(hs.window.filter.windowFocused, function(win)
        local id = win:id()
        if not id then return end
        local now = hs.timer.secondsSinceEpoch()
        local pt = hs.mouse.absolutePosition()

        -- Is this a keyboard switch? A click inside the window that just gained
        -- focus means the mouse focused it, whatever keys followed.
        local winFrame = frameOf(win)
        if not winFrame then return end
        local keyboard = pointer.isKeyboardSwitch(evidence, now)
            and not pointer.clickedInside(evidence, now, winFrame)
        local function ago(t) return t and string.format("%.2fs", now - t) or "never" end

        -- Leaving the previous window: remember where the pointer was in it. On a
        -- keyboard switch the incoming window is already raised and may cover the
        -- pointer, so leave it out when asking which window is topmost there.
        local previous = current
        if previous and previous:id() == id then
            log("focus", id, "already focused: ignored")
            return
        end
        current = win
        if previous and previous:id() and previous:id() ~= id then
            local pid = previous:id()
            local items = orderedItems()
            if keyboard then
                for i = #items, 1, -1 do if items[i].id == id then table.remove(items, i) end end
            end
            local prevFrame = frameOf(previous)
            local spot = prevFrame and pointer.record(pt, prevFrame, pointer.topmostAt(items, pt), pid)
            if spot then spots[pid] = spot end
        end

        if not keyboard then
            log("focus", id, "not a keyboard switch; key", ago(evidence.lastKey), "mouse", ago(evidence.lastMouse))
            return
        end
        local keyAge = ago(evidence.lastKey)
        pointer.consume(evidence)
        local target = pointer.destination(pt, winFrame, spots[id], {screens = screenFrames()})
        log("focus", id, target and ("move to " .. target.x .. "," .. target.y) or "stay", spots[id] and "(spot)" or "(no spot)", "key", keyAge)
        if not target then return end
        ownMoveAt = now
        hs.mouse.absolutePosition(target)
        if opts.postMoveEvent then
            hs.eventtap.event.newMouseEvent(types.mouseMoved, target):post()
        end
    end)
    M.filter:subscribe(hs.window.filter.windowDestroyed, function(win)
        local id = win:id()
        if id then spots[id] = nil end
    end)

    M.spots = spots -- exposed for debugging from `hs -c`
    return M
end

return M
