-- Hammerspoon: directional positioning and focus.
-- Disable conflicting shortcuts in Magnet before reloading this file.
-- Move/resize: Control + Option + arrow.
-- Maximize:    Control + Option + Return.-- Focus:       Control + Option + Command + arrow.
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
for key, spec in pairs(directions) do
    local direction = spec
    hs.hotkey.bind(moveModifiers, key, function() moveWindow(direction) end)
    hs.hotkey.bind(focusModifiers, key, function()
        -- Original focus behaviour: avoid obscured windows, strict direction.
        windows[direction.focus](windows, nil, true, true)
    end)
end
