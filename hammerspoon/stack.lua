-- Window-stack cycling: pure logic, no hs.* dependencies (see stack-tests.lua).
--
-- A "stack" is the focused window plus every window that overlaps it by more
-- than a fraction of the focused window's area, in true front-to-back order.
-- A window that is itself mostly covered by the focused one also counts, as
-- long as it is not tiny (so a half-width window and the full-width window it
-- sits on are in each other's stacks, but a small floater isn't).
-- Focusing a window raises it, so stepping through the live z-order only ever
-- swaps the top two; instead the order is snapshotted on the first keypress and
-- reused while keypresses keep coming, like cmd-tab.
--
-- A window item is {id = <number>, title = <string>, frame = {x, y, w, h}}.
local M = {}

local function area(f) return f.w * f.h end

local function overlapArea(a, b)
    local w = math.min(a.x + a.w, b.x + b.w) - math.max(a.x, b.x)
    local h = math.min(a.y + a.h, b.y + b.h) - math.max(a.y, b.y)
    if w <= 0 or h <= 0 then return 0 end
    return w * h
end

-- items: front-to-back list. Returns the stack (front-to-back) and the index of
-- the focused window in it, or nil if the focused window isn't in items.
function M.select(items, focusedId, minFraction, minSizeRatio)
    minSizeRatio = minSizeRatio or 0.25
    local focused
    for _, item in ipairs(items) do
        if item.id == focusedId then focused = item break end
    end
    if not focused then return nil end

    local stack, index = {}, nil
    for _, item in ipairs(items) do
        local overlap = overlapArea(focused.frame, item.frame)
        if item.id == focusedId
            or overlap > minFraction * area(focused.frame)
            or (overlap > minFraction * area(item.frame)
                and area(item.frame) >= minSizeRatio * area(focused.frame)) then
            stack[#stack + 1] = item
            if item.id == focusedId then index = #stack end
        end
    end
    return stack, index
end

-- delta: +1 steps deeper (towards the back), -1 steps back up; both wrap.
-- state: what the previous call returned, or nil.
-- Returns target item, its 1-based position, stack size, new state. The target
-- is nil if the focused window isn't known or is alone in its stack.
function M.cycle(state, items, focusedId, delta, now, opts)
    opts = opts or {}
    local timeout = opts.timeout or 1.0
    local minFraction = opts.minFraction or 0.5

    local order, index
    if state and now - state.at <= timeout and state.order[state.index].id == focusedId then
        order, index = state.order, state.index
    else
        order, index = M.select(items, focusedId, minFraction)
    end
    if not order or #order < 2 then return nil, nil, order and #order or 0, nil end

    index = (index - 1 + delta) % #order + 1
    return order[index], index, #order, {order = order, index = index, at = now}
end

return M
