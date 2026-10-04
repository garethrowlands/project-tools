-- demoStage: the Hammerspoon half of kitty/demo (see README.md there).
-- play drives it through the hs CLI: it pins and frames the kitty window,
-- glides and clicks the pointer with real mouse events (so kitty's spotlight
-- and ripple shaders see them) and arms an abort hotkey for the run.
-- Functions return "ok" (or JSON) on success, an explanation otherwise.

local M = {}

local main, savedFrame, pidFile, glideTimer, abortKey
local events = hs.eventtap.event

local function postMove(p)
  events.newMouseEvent(events.types.mouseMoved, p):post()
end

local function stopGlide()
  if glideTimer then glideTimer:stop(); glideTimer = nil end
end

-- Pin the focused (kitty) window, make it fill its screen (the user tiles
-- windows full, half or quarter screen), park the pointer in its middle and
-- arm Ctrl+Alt+Cmd+. to abort the run.
function M.begin(pidPath)
  main = hs.window.focusedWindow()
  if not main then return "no focused window" end
  pidFile = pidPath
  savedFrame = main:frame()
  main:setFrame(main:screen():frame(), 0)
  local f = main:frame()
  postMove({x = f.x + f.w / 2, y = f.y + f.h / 2})
  abortKey = abortKey or hs.hotkey.bind({"ctrl", "alt", "cmd"}, ".", M.abort)
  return "ok"
end

function M.frame()
  if not main then return "no pinned window" end
  local f = main:frame()
  return hs.json.encode({x = f.x, y = f.y, w = f.w, h = f.h})
end

-- Tile the screen: the pinned window on the left half, the window titled
-- `title` on the right half.
function M.tileBeside(title)
  local win = hs.window.get(title)
  if not (main and win) then return "no window titled " .. title end
  local s = main:screen():frame()
  main:setFrame({x = s.x, y = s.y, w = s.w / 2, h = s.h}, 0)
  win:setFrame({x = s.x + s.w / 2, y = s.y, w = s.w / 2, h = s.h}, 0)
  return "ok"
end

-- Give the pinned window its whole screen again.
function M.fill()
  if not main then return "no pinned window" end
  main:setFrame(main:screen():frame(), 0)
  return "ok"
end

-- Ease (in-out) the pointer to (x, y) over ms milliseconds, at about 60 Hz.
function M.glide(x, y, ms)
  stopGlide()
  local from = hs.mouse.absolutePosition()
  local start, dur = hs.timer.secondsSinceEpoch(), math.max(ms or 700, 1) / 1000
  glideTimer = hs.timer.doEvery(1 / 60, function()
    local t = math.min((hs.timer.secondsSinceEpoch() - start) / dur, 1)
    local e = t < 0.5 and 2 * t * t or 1 - (-2 * t + 2) ^ 2 / 2
    postMove({x = from.x + (x - from.x) * e, y = from.y + (y - from.y) * e})
    if t >= 1 then stopGlide() end
  end)
  return "ok"
end

-- Left click at the pointer, with modifiers such as {"cmd"}.
function M.click(mods)
  local p = hs.mouse.absolutePosition()
  events.newMouseEvent(events.types.leftMouseDown, p, mods or {}):post()
  hs.timer.usleep(40000)
  events.newMouseEvent(events.types.leftMouseUp, p, mods or {}):post()
  return "ok"
end

function M.notify(text)
  hs.notify.new({title = "kitty demo", informativeText = text}):send()
  return "ok"
end

-- Stop gliding and signal play's director; its trap then cleans up.
function M.abort()
  stopGlide()
  local f = pidFile and io.open(pidFile)
  if not f then return "not running" end
  local pid = f:read("l")
  f:close()
  if pid and pid:match("^%d+$") then os.execute("kill -TERM " .. pid) end
  return "ok"
end

-- End of a run (play's cleanup): restore the frame and disarm the hotkey.
function M.finish()
  stopGlide()
  if main and savedFrame then main:setFrame(savedFrame, 0) end
  if abortKey then abortKey:delete(); abortKey = nil end
  main, savedFrame, pidFile = nil, nil, nil
  return "ok"
end

-- Setup check, from a kitty pane:  hs -c 'return demoStage.selftest()'
-- Pins the focused window, glides the pointer round a 200-point square in
-- its middle, and reports the frame and whether Accessibility is granted.
function M.selftest()
  main = hs.window.focusedWindow()
  if not main then return "no focused window" end
  local f = main:frame()
  local cx, cy = f.x + f.w / 2, f.y + f.h / 2
  local corners = {{cx - 100, cy - 100}, {cx + 100, cy - 100}, {cx + 100, cy + 100}, {cx - 100, cy + 100}}
  local i = 0
  hs.timer.doUntil(function() return i >= #corners end, function()
    i = i + 1
    M.glide(corners[i][1], corners[i][2], 300)
  end, 0.4)
  return hs.json.encode({frame = {x = f.x, y = f.y, w = f.w, h = f.h}, accessibility = hs.accessibilityState()})
end

return M
