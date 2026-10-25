-- Pointer-follows-focus decisions: pure logic, no hs.* dependencies (see
-- pointer-tests.lua, and docs/superpowers/specs/2026-10-25-pointer-follows-focus-design.md).
--
-- A point is {x, y}; a frame is {x, y, w, h}; a remembered "spot" is an offset
-- {x, y} from a window's top-left corner.
local M = {}

local function inside(pt, f)
    return pt.x >= f.x and pt.x < f.x + f.w and pt.y >= f.y and pt.y < f.y + f.h
end

-- Clamp v into [lo, hi]; when the range is empty, take its midpoint.
local function clamp(v, lo, hi, mid)
    if lo > hi then return mid end
    return math.max(lo, math.min(hi, v))
end

-- Where to put the pointer when window `frame` gains focus, or nil to leave it.
-- spot: the window's remembered offset, or nil.
-- opts.inset: margin kept from the edges (default 12).
-- opts.screens: optional list of screen frames; a spot must lie on one of them.
function M.destination(pt, frame, spot, opts)
    opts = opts or {}
    local inset = opts.inset or 12

    if spot then
        local abs = {x = frame.x + spot.x, y = frame.y + spot.y}
        local onScreen = not opts.screens
        for _, s in ipairs(opts.screens or {}) do
            if inside(abs, s) then onScreen = true break end
        end
        if onScreen and inside(abs, frame) then return abs end
    end

    if inside(pt, frame) then return nil end

    return {
        x = clamp(pt.x, frame.x + inset, frame.x + frame.w - inset, frame.x + frame.w / 2),
        y = clamp(pt.y, frame.y + inset, frame.y + frame.h - inset, frame.y + frame.h / 2),
    }
end

-- The spot to remember for a window being left, or nil. Only recorded when the
-- pointer is inside the window and that window is the topmost one at the pointer.
function M.record(pt, frame, topmostId, windowId)
    if topmostId ~= windowId or not inside(pt, frame) then return nil end
    return {x = pt.x - frame.x, y = pt.y - frame.y}
end

-- items: front-to-back list of {id, frame}. The id of the first containing pt.
function M.topmostAt(items, pt)
    for _, item in ipairs(items) do
        if inside(pt, item.frame) then return item.id end
    end
    return nil
end

-- Keyboard evidence: was this focus change made from the keyboard?
-- Times are seconds, passed in; there is no clock in here.

-- window: how long after a key event a focus change still counts (see the spike).
function M.newEvidence(window)
    return {window = window or 0.5, lastKey = nil, lastMouse = nil, held = false}
end

-- A key-down or a modifier change.
function M.noteKey(state, now)
    state.lastKey = now
end

-- held: true while any modifier is down. Callers also call noteKey from the same
-- flagsChanged handler, so a modifier release counts as a key event.
function M.noteModifiers(state, held)
    state.held = held
end

-- A click, scroll or pointer movement that we did not make ourselves.
function M.noteMouse(state, now)
    state.lastMouse = now
end

-- Forget all key and mouse activity, e.g. after the event tap was disabled and
-- restarted: events may have been missed, so nothing seen so far can be trusted.
function M.reset(state)
    state.lastKey, state.lastMouse, state.lastClick, state.held = nil, nil, nil, false
end

-- A modifier was released. It counts as a key event (Cmd+Tab style switchers act
-- on the release), but not if the mouse was used since the last key event: a
-- click made while the modifier was held must not be overridden by letting go.
function M.noteRelease(state, now)
    if state.lastMouse and (not state.lastKey or state.lastMouse > state.lastKey) then return end
    state.lastKey = now
end

-- A mouse button went down at pt. Also counts as mouse activity.
function M.noteClick(state, now, pt)
    state.lastMouse = now
    state.lastClick = {at = now, pt = pt}
end

-- True if the last click was recent (within 1s) and inside frame: the mouse gave
-- that window focus, whatever keys were pressed afterwards.
function M.clickedInside(state, now, frame)
    local c = state.lastClick
    return c ~= nil and now - c.at <= 1.0 and inside(c.pt, frame)
end

-- Call once a focus change has used the evidence: one key press justifies at
-- most one move, so a repeat focus event for the same press does nothing.
function M.consume(state)
    state.lastKey = nil
end

-- True when a key event happened, nothing mouse-driven came after it, and it is
-- either recent or a modifier is still held (Cmd+Tab style switchers).
function M.isKeyboardSwitch(state, now)
    if not state.lastKey then return false end
    if state.lastMouse and state.lastMouse > state.lastKey then return false end
    return state.held or now - state.lastKey <= state.window
end

return M
