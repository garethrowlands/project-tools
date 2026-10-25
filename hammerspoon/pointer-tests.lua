-- Tests for pointer.lua. Needs no test framework; run inside Hammerspoon:
--   hs -c 'return dofile("<repo>/hammerspoon/pointer-tests.lua")'
-- Returns a summary, or errors on failure.
local here = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") or "."
local pointer = dofile(here .. "/pointer.lua")

local passed = 0
local function check(cond, label)
    if not cond then error("FAIL: " .. label, 2) end
    passed = passed + 1
end

local function same(p, x, y) return p ~= nil and p.x == x and p.y == y end

local F = {x = 100, y = 100, w = 800, h = 600}

-- destination: a remembered spot wins.
check(same(pointer.destination({x = 0, y = 0}, F, {x = 50, y = 40}), 150, 140), "remembered spot is used")

-- destination: a spot outside the frame is ignored; a pointer inside then stays.
check(pointer.destination({x = 500, y = 300}, F, {x = 900, y = 40}) == nil, "spot outside frame falls through to stay-put")

-- destination: a spot on a display that is gone is ignored.
local gone = pointer.destination({x = 0, y = 0}, {x = 900, y = 0, w = 800, h = 600}, {x = 500, y = 10},
    {screens = {{x = 0, y = 0, w = 1000, h = 800}}})
check(same(gone, 912, 12), "spot off every screen falls through to the nearest point")

-- destination: no spot, pointer already inside.
check(pointer.destination({x = 500, y = 300}, F, nil) == nil, "pointer inside stays")

-- destination: nearest point just inside the frame.
check(same(pointer.destination({x = 0, y = 300}, F, nil), 112, 300), "nearest point from the left")
check(same(pointer.destination({x = 0, y = 0}, F, nil), 112, 112), "nearest point from the top-left")
check(same(pointer.destination({x = 2000, y = 2000}, F, nil), 888, 688), "nearest point from the bottom-right")

-- destination: a window smaller than twice the inset.
check(same(pointer.destination({x = 500, y = 500}, {x = 0, y = 0, w = 10, h = 10}, nil), 5, 5), "tiny window gets its midpoint")

-- record: inside and topmost.
local spot = pointer.record({x = 150, y = 140}, F, 7, 7)
check(same(spot, 50, 40), "record gives an offset from the window's corner")
check(pointer.record({x = 0, y = 0}, F, 7, 7) == nil, "pointer outside: nothing recorded")
check(pointer.record({x = 150, y = 140}, F, 8, 7) == nil, "covered by another window: nothing recorded")

-- topmostAt.
local items = {{id = 1, frame = {x = 0, y = 0, w = 50, h = 50}}, {id = 2, frame = F}, {id = 3, frame = F}}
check(pointer.topmostAt(items, {x = 10, y = 10}) == 1, "topmostAt picks the frontmost")
check(pointer.topmostAt(items, {x = 500, y = 300}) == 2, "topmostAt skips windows not under the point")
check(pointer.topmostAt(items, {x = 5000, y = 5000}) == nil, "topmostAt with nothing under the point")

-- evidence: no events.
local e = pointer.newEvidence(0.5)
check(pointer.isKeyboardSwitch(e, 0) == false, "no events is not a keyboard switch")

-- evidence: a recent key counts, an old one does not.
e = pointer.newEvidence(0.5)
pointer.noteKey(e, 0)
check(pointer.isKeyboardSwitch(e, 0.3), "recent key counts")
check(not pointer.isKeyboardSwitch(e, 0.6), "old key does not")

-- evidence: a held modifier keeps it alive; the release is itself a key event.
e = pointer.newEvidence(0.5)
pointer.noteKey(e, 0)
pointer.noteModifiers(e, true)
check(pointer.isKeyboardSwitch(e, 2.0), "held modifier keeps the evidence")
pointer.noteKey(e, 2.1)
pointer.noteModifiers(e, false)
check(pointer.isKeyboardSwitch(e, 2.2), "modifier release counts as a key event")

-- evidence: a mouse event after the key cancels it (Cmd+Tab, then click a Contexts entry).
e = pointer.newEvidence(0.5)
pointer.noteKey(e, 0)
pointer.noteMouse(e, 0.1)
check(not pointer.isKeyboardSwitch(e, 0.2), "click after key cancels")
e = pointer.newEvidence(0.5)
pointer.noteKey(e, 0)
pointer.noteModifiers(e, true)
pointer.noteMouse(e, 1.0)
check(not pointer.isKeyboardSwitch(e, 1.1), "click cancels even with the modifier held")

-- evidence: a key after the mouse counts.
e = pointer.newEvidence(0.5)
pointer.noteMouse(e, 0)
pointer.noteKey(e, 0.1)
check(pointer.isKeyboardSwitch(e, 0.2), "key after mouse counts")

-- evidence: one key press justifies one move; a second focus event does not repeat it.
e = pointer.newEvidence(0.5)
pointer.noteKey(e, 0)
check(pointer.isKeyboardSwitch(e, 0.1), "first focus event after the key counts")
pointer.consume(e)
check(not pointer.isKeyboardSwitch(e, 0.2), "consumed evidence does not count again")
pointer.noteKey(e, 0.3)
check(pointer.isKeyboardSwitch(e, 0.4), "a fresh key press counts again")

-- evidence: releasing a modifier after a click does not override the click
-- (Cmd+Tab, click a Contexts entry while Cmd is held, then release Cmd).
e = pointer.newEvidence(0.5)
pointer.noteKey(e, 0)
pointer.noteModifiers(e, true)
pointer.noteMouse(e, 0.2)
pointer.noteRelease(e, 0.3)
pointer.noteModifiers(e, false)
check(not pointer.isKeyboardSwitch(e, 0.35), "release after a click does not count")
-- ...but a release with no mouse activity since the press still counts.
e = pointer.newEvidence(0.5)
pointer.noteKey(e, 0)
pointer.noteModifiers(e, true)
pointer.noteRelease(e, 2.0)
pointer.noteModifiers(e, false)
check(pointer.isKeyboardSwitch(e, 2.1), "release with no mouse activity counts")

-- evidence: a click inside the window that gained focus means the mouse focused it,
-- even if keys were pressed after the click.
e = pointer.newEvidence(0.5)
pointer.noteClick(e, 0, {x = 500, y = 300})
pointer.noteKey(e, 0.1)
check(pointer.clickedInside(e, 0.2, F), "recent click inside the window")
check(not pointer.clickedInside(e, 0.2, {x = 2000, y = 0, w = 100, h = 100}), "click was elsewhere")
check(not pointer.clickedInside(e, 5, F), "old click does not count")
check(not pointer.clickedInside(pointer.newEvidence(0.5), 0, F), "no click at all")

return string.format("pointer-tests: %d checks passed", passed)
