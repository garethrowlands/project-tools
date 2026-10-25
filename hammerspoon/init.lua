-- Hammerspoon: directional positioning and focus.
-- Disable conflicting shortcuts in Magnet before reloading this file.
-- Move/resize: Control + Option + arrow.
-- Maximize:    Control + Option + Return.
-- Focus:       Control + Option + Command + arrow.
-- Stack:       Control + Option + Command + ] / [ steps down / up the windows stacked on the focused one.
require("hs.ipc")
-- ~/.hammerspoon/init.lua is a symlink into the repo; resolve it to find the repo.
local repoDir = hs.fs.pathToAbsolute(hs.configdir .. "/init.lua"):match("^(.*)/hammerspoon/[^/]*$")
demoStage = dofile(repoDir .. "/kitty/demo/stage.lua")

-- Machine-specific or private settings go in an untracked local.lua beside this file.
local localConfig = hs.fs.pathToAbsolute(hs.configdir .. "/init.lua"):match("^(.*)/[^/]*$") .. "/local.lua"
if hs.fs.attributes(localConfig) then dofile(localConfig) end

local moveModifiers = {"ctrl", "alt"}
local focusModifiers = {"ctrl", "alt", "cmd"}
local tolerance = 16 -- points; accommodates small gaps and rounding
local midpointTolerance = 2 -- tighter so manual resizing isn't mistaken for a half

-- Each axis has three recognised states: full, first half, second half.
-- Unrecognised/floating windows snap to the requested half on that axis;
-- their position and size on the other axis stay unchanged.
local function nextAxis(position, size, origin, extent, direction)
    local function near(a, b) return math.abs(a - b) <= tolerance end
    local atFirst = near(position, origin)
    local atSecond = near(position + size, origin + extent)
    local midpoint = origin + extent / 2
    local firstHalf = atFirst and math.abs(position + size - midpoint) <= midpointTolerance
    local secondHalf = atSecond and math.abs(position - midpoint) <= midpointTolerance

    if atFirst and atSecond then
        return origin + (direction > 0 and extent / 2 or 0), extent / 2, false
    end
    -- An inward press moves a manually shortened free edge to the midpoint
    -- first, then to the far screen edge on the following press.
    if direction > 0 and atFirst then
        local edge = position + size
        local targetEdge = edge < midpoint - midpointTolerance and midpoint or origin + extent
        return origin, targetEdge - origin, false
    end
    if direction < 0 and atSecond then
        local targetEdge = position > midpoint + midpointTolerance and midpoint or origin
        return targetEdge, origin + extent - targetEdge, false
    end
    if (direction < 0 and firstHalf) or (direction > 0 and secondHalf) then
        return position, size, true -- outward: try the next monitor
    end
    return origin + (direction > 0 and extent / 2 or 0), extent / 2, false
end

local directions = {
    Left  = {axis = "x", size = "w", sign = -1, screen = "toWest",  focus = "focusWindowWest"},
    Right = {axis = "x", size = "w", sign =  1, screen = "toEast",  focus = "focusWindowEast"},
    Up    = {axis = "y", size = "h", sign = -1, screen = "toNorth", focus = "focusWindowNorth"},
    Down  = {axis = "y", size = "h", sign =  1, screen = "toSouth", focus = "focusWindowSouth"},
}

-- window id -> axis -> {position, size} we last asked for, and what the app gave us.
local lastSnap = {}
local axes = {x = "w", y = "h"}

local function moveWindow(direction)
    local win = hs.window.focusedWindow()
    if not win or not win:isStandard() then return end
    if win:isFullScreen() then
        hs.alert.show("Exit macOS full screen before positioning this window")
        return
    end

    local screen = win:screen()
    if not screen then return end
    local bounds = screen:frame() -- usable area, excluding menu bar and Dock
    local frame = win:frame()
    local id = win:id()

    -- Some apps (e.g. Miro, with a minimum height) can't take the exact frame
    -- we ask for, which would stop the window being recognised as a half or
    -- full. If it hasn't moved since our last snap on an axis, treat it as
    -- being in the state we asked for.
    local function effective(axis)
        local sizeKey = axes[axis]
        local last = id and lastSnap[id] and lastSnap[id][axis]
        if last and math.abs(last.actualPosition - frame[axis]) <= midpointTolerance
            and math.abs(last.actualSize - frame[sizeKey]) <= midpointTolerance then
            return last.position, last.size
        end
        return frame[axis], frame[sizeKey]
    end

    local axis, sizeKey = direction.axis, direction.size
    local currentPosition, currentSize = effective(axis)
    local position, size, crossScreen = nextAxis(
        currentPosition, currentSize, bounds[axis], bounds[sizeKey], direction.sign
    )

    local requested -- the frame we ask for
    if crossScreen then
        local destination = screen[direction.screen](screen, nil, true)
        if not destination then return end
        local target = destination:frame()
        -- Preserve proportional size and position on both axes, from the
        -- remembered (not the refused) frame, entering the destination
        -- display at its near edge.
        local x, w = effective("x")
        local y, h = effective("y")
        requested = {
            x = target.x + (x - bounds.x) / bounds.w * target.w,
            y = target.y + (y - bounds.y) / bounds.h * target.h,
            w = w / bounds.w * target.w,
            h = h / bounds.h * target.h,
        }
        requested[axis] = target[axis]
            + (direction.sign < 0 and (target[sizeKey] - requested[sizeKey]) or 0)
    else
        requested = {x = frame.x, y = frame.y, w = frame.w, h = frame.h}
        requested[axis] = position
        requested[sizeKey] = size
    end
    -- No animation, so the next keypress sees the completed position.
    win:setFrame(requested, 0)

    if id then
        local actual = win:frame()
        local snaps = lastSnap[id] or {}
        -- A move within a screen only changes this axis; the other keeps its own record.
        -- A move to another screen changes both.
        if crossScreen then snaps = {} end
        for a, k in pairs(axes) do
            if crossScreen or a == axis then
                snaps[a] = {
                    position = requested[a], size = requested[k],
                    actualPosition = actual[a], actualSize = actual[k],
                }
            end
        end
        lastSnap[id] = snaps
    end
end

local function maximizeWindow()
    local win = hs.window.focusedWindow()
    if not win or not win:isStandard() then return end
    if win:isFullScreen() then
        hs.alert.show("Exit macOS full screen before positioning this window")
        return
    end
    local screen = win:screen()
    if not screen then return end
    win:setFrame(screen:frame(), 0) -- usable area, excluding menu bar and Dock
end

hs.hotkey.bind(moveModifiers, "return", maximizeWindow)

local windows = hs.window.filter.defaultCurrentSpace

-- Set true to append every focus keypress to ~/.hammerspoon/focus-debug.log:
-- the window we left, every candidate the filter saw, and where we landed.
local focusDebug = false
local focusLog = hs.configdir .. "/focus-debug.log"

local function describeWindow(w)
    local f = w:frame()
    local app = w:application()
    return string.format("%s | %s | id%s | %d,%d %dx%d | std=%s | screen=%s",
        app and app:name() or "?", (w:title() or ""):sub(1, 40), tostring(w:id()),
        f.x, f.y, f.w, f.h, tostring(w:isStandard()),
        w:screen() and w:screen():name() or "?")
end

local function logFocus(name, run)
    local out = {os.date("== %Y-%m-%d %H:%M:%S ") .. name}
    local from = hs.window.focusedWindow()
    out[#out + 1] = "  from: " .. (from and describeWindow(from) or "none")
    for _, w in ipairs(windows:getWindows()) do
        out[#out + 1] = "  cand: " .. describeWindow(w)
    end
    run()
    hs.timer.doAfter(0.15, function()
        local to = hs.window.focusedWindow()
        out[#out + 1] = "  land: " .. (to and describeWindow(to) or "none")
        local fh = io.open(focusLog, "a")
        if fh then fh:write(table.concat(out, "\n"), "\n"); fh:close() end
    end)
end

for key, spec in pairs(directions) do
    local direction = spec
    hs.hotkey.bind(moveModifiers, key, function() moveWindow(direction) end)
    hs.hotkey.bind(focusModifiers, key, function()
        -- Original focus behaviour: avoid obscured windows, strict direction.
        local function focus() windows[direction.focus](windows, nil, true, true) end
        if focusDebug then logFocus(key, focus) else focus() end
    end)
end

-- Step through the stack of windows overlapping the focused one, in true
-- front-to-back order: "]" goes deeper, "[" comes back up. See stack.lua.
local stack = dofile(hs.fs.pathToAbsolute(hs.configdir .. "/init.lua"):match("^(.*)/[^/]*$") .. "/stack.lua")
local stackState, stackAlert, stackHud, stackHudTimer

local function stackItems()
    local items, byId = {}, {}
    for _, w in ipairs(hs.window.orderedWindows()) do
        local id = w:id()
        if id and w:isStandard() then
            local f = w:frame()
            local app = w:application()
            items[#items + 1] = {
                id = id, title = w:title() or "", app = app and app:name() or "",
                frame = {x = f.x, y = f.y, w = f.w, h = f.h},
            }
            byId[id] = w
        end
    end
    return items, byId
end

local function hideStackHud(fade)
    if stackHudTimer then stackHudTimer:stop() stackHudTimer = nil end
    if stackHud then stackHud:delete(fade) stackHud = nil end
end

-- A list of the whole stack, current window highlighted, centred on the screen.
-- It never takes focus; it fades out once the keypresses stop.
local function showStackHud(order, index, screen)
    hideStackHud(0)
    local maxRows, rowH, pad, headerH, width = 9, 30, 14, 30, 560
    local first = math.max(1, math.min(index - math.floor(maxRows / 2), #order - maxRows + 1))
    local last = math.min(#order, first + maxRows - 1)
    local height = pad * 2 + headerH + (last - first + 1) * rowH
    local sf = screen:frame()

    local c = hs.canvas.new({x = sf.x + (sf.w - width) / 2, y = sf.y + (sf.h - height) / 2, w = width, h = height})
    c:level(hs.canvas.windowLevels.overlay)
    c:appendElements({
        type = "rectangle", action = "fill", roundedRectRadii = {xRadius = 12, yRadius = 12},
        fillColor = {white = 0.1, alpha = 0.92}, frame = {x = 0, y = 0, w = width, h = height},
    }, {
        type = "text", text = string.format("Stack  %d/%d", index, #order),
        textColor = {white = 0.65}, textSize = 14, textAlignment = "left",
        frame = {x = pad, y = pad, w = width - 2 * pad, h = headerH},
    })
    for i = first, last do
        local y = pad + headerH + (i - first) * rowH
        local item = order[i]
        local label = item.app ~= "" and (item.app .. " — " .. item.title) or item.title
        if #label > 70 then label = label:sub(1, 69) .. "…" end
        if i == index then
            c:appendElements({
                type = "rectangle", action = "fill", roundedRectRadii = {xRadius = 6, yRadius = 6},
                fillColor = {red = 0.2, green = 0.5, blue = 1, alpha = 0.85},
                frame = {x = pad / 2, y = y, w = width - pad, h = rowH},
            })
        end
        c:appendElements({
            type = "text", text = label, textColor = {white = i == index and 1 or 0.8}, textSize = 16,
            textAlignment = "left", textLineBreak = "truncateTail",
            frame = {x = pad + 4, y = y + 4, w = width - 2 * pad - 8, h = rowH - 4},
        })
    end
    c:show()
    stackHud = c
    stackHudTimer = hs.timer.doAfter(1.2, function() hideStackHud(0.2) end)
end

local function stepStack(delta)
    local focused = hs.window.focusedWindow()
    if not focused then return end
    local items, byId = stackItems()
    local target, position, count, state = stack.cycle(
        stackState, items, focused:id(), delta, hs.timer.secondsSinceEpoch())
    if stackAlert then hs.alert.closeSpecific(stackAlert, 0) stackAlert = nil end
    if not target then
        hideStackHud(0)
        stackAlert = hs.alert.show(count < 2 and "Only window in its stack" or "No stack", 0.8)
        return
    end
    stackState = state
    -- The snapshot can name a window that has since closed.
    local win = byId[target.id]
    if win then win:focus() end
    showStackHud(state.order, position, (win and win:screen()) or focused:screen() or hs.screen.mainScreen())
end

hs.hotkey.bind(focusModifiers, "]", function() stepStack(1) end)
hs.hotkey.bind(focusModifiers, "[", function() stepStack(-1) end)

-- Move the pointer with keyboard focus changes (Hammerspoon keys, Contexts, Cmd+Tab).
-- See pointer.lua / pointer-follow.lua.
dofile(hs.fs.pathToAbsolute(hs.configdir .. "/init.lua"):match("^(.*)/[^/]*$") .. "/pointer-follow.lua").start({debug = false})
