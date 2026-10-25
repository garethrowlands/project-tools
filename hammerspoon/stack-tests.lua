-- Tests for stack.lua. Needs no test framework; run inside Hammerspoon:
--   hs -c 'return dofile("<repo>/hammerspoon/stack-tests.lua")'
-- Returns a summary, or errors on failure.
local here = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") or "."
local stack = dofile(here .. "/stack.lua")

local passed = 0
local function check(cond, label)
    if not cond then error("FAIL: " .. label, 2) end
    passed = passed + 1
end

local function win(id, x, y, w, h) return {id = id, title = "w" .. id, frame = {x = x, y = y, w = w, h = h}} end

-- Front to back. 1,2,3 share the left half; 4,5 share the right half; 6 is a
-- small window sitting on the left half; 7 is on another screen.
local items = {
    win(1, 0, 0, 1920, 2130), win(6, 100, 500, 230, 400), win(2, 0, 0, 1920, 2130),
    win(4, 1920, 0, 1920, 2130), win(3, 0, 0, 1800, 1500), win(5, 1920, 0, 1920, 2130),
    win(7, 3840, 1400, 1728, 1084),
}

local function ids(list) local t = {} for i, w in ipairs(list) do t[i] = w.id end return table.concat(t, ",") end

-- select: left-half stack drops the small floating window (6) and other columns.
local s, i = stack.select(items, 1, 0.5)
check(ids(s) == "1,2,3", "select left-half stack front-to-back, got " .. ids(s))
check(i == 1, "select reports focused index")
s, i = stack.select(items, 5, 0.5)
check(ids(s) == "4,5" and i == 2, "select right-half stack")
check(stack.select(items, 99, 0.5) == nil, "select unknown focused window")
s = stack.select(items, 7, 0.5)
check(ids(s) == "7", "select lone window")

-- Symmetry: a half-width window lying on a full-width one is in its stack, and
-- the full-width one is in the half-width window's. A small floater is not.
local wide = {
    win(1, 0, 0, 3840, 2130), win(2, 1920, 0, 1920, 2130), win(3, 100, 500, 230, 400),
}
s = stack.select(wide, 2, 0.5)
check(ids(s) == "1,2", "half-width window's stack includes the full-width one, got " .. ids(s))
s = stack.select(wide, 1, 0.5)
check(ids(s) == "1,2", "full-width window's stack includes the half-width one, got " .. ids(s))

-- cycle: first press snapshots, later presses walk the snapshot even though the
-- live order changes under us (focusing raises a window).
local t0 = 100
local target, pos, n, st = stack.cycle(nil, items, 1, 1, t0)
check(target.id == 2 and pos == 2 and n == 3, "first step goes to next window down")
local raised = {win(2, 0, 0, 1920, 2130), win(1, 0, 0, 1920, 2130), win(3, 0, 0, 1800, 1500)}
target, pos, n, st = stack.cycle(st, raised, 2, 1, t0 + 0.5)
check(target.id == 3 and pos == 3, "second step walks the snapshot, not the live order")
target, pos, n, st = stack.cycle(st, raised, 3, 1, t0 + 0.9)
check(target.id == 1 and pos == 1, "stepping past the back wraps to the front")
target, pos, n, st = stack.cycle(st, raised, 1, -1, t0 + 1.2)
check(target.id == 3 and pos == 3, "stepping back from the front wraps to the back")

-- cycle: timeout, and focus moved elsewhere, both take a fresh snapshot.
_, _, _, st = stack.cycle(nil, items, 1, 1, t0)
target = stack.cycle(st, raised, 2, 1, t0 + 5)
check(target.id == 1, "after the timeout the live order is used afresh")
_, _, _, st = stack.cycle(nil, items, 1, 1, t0)
target = stack.cycle(st, items, 4, 1, t0 + 0.2)
check(target.id == 5, "focus moved to another stack: fresh snapshot")

-- cycle: lone or unknown window.
target, pos, n, st = stack.cycle(nil, items, 7, 1, t0)
check(target == nil and n == 1 and st == nil, "lone window has nowhere to go")
target, pos, n = stack.cycle(nil, items, 99, 1, t0)
check(target == nil and n == 0, "unknown focused window")

return "stack-tests: " .. passed .. " checks passed"
