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
    local current = nil       -- the window that currently has focus (as we last saw)
    local ownMoveAt = -1      -- when we last moved the pointer ourselves

    local function frameOf(w) local f = w:frame() return {x = f.x, y = f.y, w = f.w, h = f.h} end

    local function orderedItems()
        local items = {}
        for _, w in ipairs(hs.window.orderedWindows()) do
            local id = w:id()
            if id and w:isStandard() then items[#items + 1] = {id = id, frame = frameOf(w)} end
        end
        return items
    end

    local function screenFrames()
        local list = {}
        for _, s in ipairs(hs.screen.allScreens()) do
            local f = s:frame()
            list[#list + 1] = {x = f.x, y = f.y, w = f.w, h = f.h}
        end
        return list
    end

    M.tap = hs.eventtap.new({
        types.keyDown, types.flagsChanged, types.leftMouseDown, types.rightMouseDown,
        types.otherMouseDown, types.scrollWheel, types.mouseMoved,
    }, function(e)
        local now = hs.timer.secondsSinceEpoch()
        local t = e:getType()
        if t == types.keyDown then
            pointer.noteKey(evidence, now)
        elseif t == types.flagsChanged then
            pointer.noteKey(evidence, now)
            pointer.noteModifiers(evidence, next(e:getFlags()) ~= nil)
        elseif t ~= types.mouseMoved or now - ownMoveAt > 0.1 then
            pointer.noteMouse(evidence, now)
        end
        return false
    end)
    M.tap:start()

    M.filter = hs.window.filter.new()
    M.filter:subscribe(hs.window.filter.windowFocused, function(win)
        local id = win:id()
        if not id then return end
        local now = hs.timer.secondsSinceEpoch()
        local pt = hs.mouse.absolutePosition()

        -- Leaving the previous window: remember where the pointer was in it.
        local previous = current
        current = win
        if previous and previous:id() and previous:id() ~= id then
            local pid = previous:id()
            local spot = pointer.record(pt, frameOf(previous), pointer.topmostAt(orderedItems(), pt), pid)
            if spot then spots[pid] = spot end
        end

        if not pointer.isKeyboardSwitch(evidence, now) then
            log("focus", id, "not a keyboard switch")
            return
        end
        local target = pointer.destination(pt, frameOf(win), spots[id], {screens = screenFrames()})
        log("focus", id, target and ("move to " .. target.x .. "," .. target.y) or "stay")
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
