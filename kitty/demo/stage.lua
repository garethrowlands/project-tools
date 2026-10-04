-- demoStage: the Hammerspoon half of kitty/demo (see README.md there).
-- play drives it through the hs CLI: it pins and frames the kitty window,
-- glides and clicks the pointer with real mouse events (so kitty's spotlight
-- and ripple shaders see them) and arms an abort hotkey for the run.
-- Functions return "ok" (or JSON) on success, an explanation otherwise.

local M = {}

-- When this file was last modified as Hammerspoon loaded it; play compares
-- it with the file on disk and asks for a reload if the file is newer.
M.loadedMtime = math.floor(hs.fs.attributes(debug.getinfo(1, "S").source:sub(2), "modification") or 0)

local main, savedFrame, pidFile, glideTimer, abortKey
-- The other app's window opened by openOther, and whether that app was
-- already running (if not, closeOther quits it again).
local OTHER_APP = "com.apple.TextEdit"
local otherTitle, otherWasRunning, otherWin, placeTimer
local events = hs.eventtap.event

local function postMove(p)
  events.newMouseEvent(events.types.mouseMoved, p):post()
end

local function stopGlide()
  if glideTimer then glideTimer:stop(); glideTimer = nil end
end

-- Key badge: the keys the director just pressed, at the bottom centre of
-- the screen, above kitty's tab bar; a new press replaces it.
local badge, badgeTimer

local function showBadge(label)
  if badgeTimer then badgeTimer:stop() end
  if badge then badge:delete() end
  local s = (main and main:screen() or hs.screen.mainScreen()):frame()
  local w, h = 240, 84
  badge = hs.canvas.new({x = s.x + (s.w - w) / 2, y = s.y + s.h - h - 70, w = w, h = h})
  badge:appendElements(
    {type = "rectangle", action = "fill", fillColor = {white = 0.08, alpha = 0.85},
     roundedRectRadii = {xRadius = 16, yRadius = 16}},
    {type = "text", frame = {x = 0, y = 12, w = w, h = h - 12},
     text = hs.styledtext.new(label, {font = {name = "Menlo", size = 40}, color = {white = 0.95},
                                      paragraphStyle = {alignment = "center"}})})
  badge:level(hs.canvas.windowLevels.overlay)
  badge:show()
  badgeTimer = hs.timer.doAfter(1.2, function() if badge then badge:hide(0.3) end end)
end

-- Post a real keystroke (mods e.g. {"shift","cmd"}, key e.g. "return") to
-- the frontmost app, showing `label` as the badge.
function M.press(mods, key, label)
  -- Never send keys to another app: a stray Cmd+T or Cmd+Shift+Enter there
  -- would act before the beat's next wait noticed anything.
  local front = hs.application.frontmostApplication()
  if not (front and front:bundleID() == "net.kovidgoyal.kitty") then
    return "kitty is not the frontmost app"
  end
  showBadge(label)
  hs.eventtap.keyStroke(mods, key, 20000)
  return "ok"
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

-- Give the pinned window its whole screen again.
function M.fill()
  if not main then return "no pinned window" end
  main:setFrame(main:screen():frame(), 0)
  return "ok"
end

local function halves()
  local s = main:screen():frame()
  return {x = s.x, y = s.y, w = s.w / 2, h = s.h}, {x = s.x + s.w / 2, y = s.y, w = s.w / 2, h = s.h}
end

-- Is `win` the window openOther opened? Its title is the file name, or the
-- name without its extension when Finder hides extensions.
local function isOther(win)
  local t = win:title()
  return t == otherTitle or t == otherTitle:gsub("%.[^.]*$", "")
end

-- Make room (the pinned window takes the left half), then open `path` in
-- TextEdit (-F: no restored windows if it wasn't running). A 10 ms watcher
-- moves its window to the right half the moment it appears and focuses it,
-- so it is never seen at TextEdit's default spot for more than a frame or
-- two. otherPlaced() reports when that has happened.
function M.openOther(path)
  if not main then return "no pinned window" end
  otherWasRunning = hs.application.get(OTHER_APP) ~= nil
  otherTitle, otherWin = path:match("[^/]+$"), nil
  local left, right = halves()
  main:setFrame(left, 0)
  local deadline = hs.timer.secondsSinceEpoch() + 5
  if placeTimer then placeTimer:stop() end
  placeTimer = hs.timer.doEvery(0.01, function()
    local app = hs.application.get(OTHER_APP)
    for _, win in ipairs(app and app:allWindows() or {}) do
      if isOther(win) then
        win:setFrame(right, 0)
        win:focus()
        otherWin = win
        placeTimer:stop(); placeTimer = nil
        return
      end
    end
    if hs.timer.secondsSinceEpoch() > deadline then placeTimer:stop(); placeTimer = nil end
  end)
  hs.task.new("/usr/bin/open", nil, {"-g", "-F", "-b", OTHER_APP, path}):start()
  return "ok"
end

function M.otherPlaced()
  return otherWin and "ok" or "not yet"
end

function M.focusOther(title)
  local win = otherWin or hs.window.get(title)
  if not win then return "no window titled " .. title end
  win:focus()
  return "ok"
end

function M.focusMain()
  if not main then return "no pinned window" end
  main:focus()
  return "ok"
end

-- Close the window openOther opened (never edited, so no save prompt), and
-- quit TextEdit if it wasn't running before.
function M.closeOther(title)
  if placeTimer then placeTimer:stop(); placeTimer = nil end
  local win = otherWin or hs.window.get(title)
  if win then win:close() end
  if otherWasRunning == false then
    local app = hs.application.get(OTHER_APP)
    if app then app:kill() end
  end
  otherTitle, otherWasRunning, otherWin = nil, nil, nil
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
  if badge then badge:delete(); badge = nil end
  if otherTitle then M.closeOther(otherTitle) end
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
  showBadge("⌘→")
  return hs.json.encode({frame = {x = f.x, y = f.y, w = f.w, h = f.h}, accessibility = hs.accessibilityState()})
end

return M
