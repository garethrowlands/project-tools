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
-- The windows openStack opened, back to front (their file names, and the
-- windows once placed), and whether the app was already running (if not,
-- closeStack quits it again).
local stackNames, stackWins, stackWasRunning, stackTimer = {}, {}, nil, nil
-- The app window a launcher key opened (VS Code, Edge), tiled beside kitty by
-- tileNext: {bundle, win, savedFrame (if it was already open), wasRunning}.
local EDGE = "com.microsoft.edgemac"
local tiled, tileTimer
-- play --record: the screencapture task recording the pinned window's display.
local recordTask
local events = hs.eventtap.event

local function postMove(p)
  events.newMouseEvent(events.types.mouseMoved, p):post()
end

local function stopGlide()
  if glideTimer then glideTimer:stop(); glideTimer = nil end
end

-- Key badge: the keys the director is about to press, at the bottom centre
-- of the screen, above kitty's tab bar; a new press replaces it. It appears
-- BADGE_LEAD seconds before the keystroke, so viewers read the key first,
-- and stays BADGE_HOLD seconds after it.
local BADGE_LEAD, BADGE_HOLD = 0.7, 1.2
local badge, badgeTimer, pressTimer

local function showBadge(label, hold)
  if badgeTimer then badgeTimer:stop() end
  if badge then badge:delete() end
  local s = (main and main:screen() or hs.screen.mainScreen()):frame()
  local w, h = 360, 120
  badge = hs.canvas.new({x = s.x + (s.w - w) / 2, y = s.y + s.h - h - 70, w = w, h = h})
  badge:appendElements(
    {type = "rectangle", action = "strokeAndFill", fillColor = {white = 0.08, alpha = 0.9},
     strokeColor = {red = 0.98, green = 0.70, blue = 0.53}, strokeWidth = 3,
     roundedRectRadii = {xRadius = 20, yRadius = 20}},
    {type = "text", frame = {x = 0, y = 18, w = w, h = h - 18},
     text = hs.styledtext.new(label, {font = {name = "Menlo", size = 64}, color = {white = 0.97},
                                      paragraphStyle = {alignment = "center"}})})
  badge:level(hs.canvas.windowLevels.overlay)
  badge:show()
  badgeTimer = hs.timer.doAfter(hold or BADGE_HOLD, function() if badge then badge:hide(0.3) end end)
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
  -- ...and the pinned kitty, not another instance (chapter 3 runs its own)
  if main and front:pid() ~= main:application():pid() then
    return "another kitty is the frontmost app"
  end
  -- The keystroke follows the badge after BADGE_LEAD, on a timer (a blocking
  -- sleep would stop the badge drawing); every press in a beat is followed by
  -- a wait for its effect, so the director needs no change.
  showBadge(label, BADGE_LEAD + BADGE_HOLD)
  if pressTimer then pressTimer:stop() end
  pressTimer = hs.timer.doAfter(BADGE_LEAD, function()
    pressTimer = nil
    hs.eventtap.keyStroke(mods, key, 20000)
  end)
  return "ok"
end

-- Like press, but for keys Hammerspoon itself acts on, with the other app
-- (TextEdit, where openStack left the focus) frontmost.
function M.pressOther(mods, key, label)
  local front = hs.application.frontmostApplication()
  if not (front and front:bundleID() == OTHER_APP) then
    return "the other app is not the frontmost app"
  end
  showBadge(label, BADGE_LEAD + BADGE_HOLD)
  if pressTimer then pressTimer:stop() end
  pressTimer = hs.timer.doAfter(BADGE_LEAD, function()
    pressTimer = nil
    hs.eventtap.keyStroke(mods, key, 20000)
  end)
  return "ok"
end

-- Where begin parks the pointer, as fractions of the kitty window.
local PARK = {x = 0.8, y = 0.2}

-- Pin the focused (kitty) window, make it fill its screen (the user tiles
-- windows full, half or quarter screen), park the pointer near its top right
-- (clear of the slide text; dead centre looked unnatural) and
-- arm Ctrl+Alt+Cmd+. to abort the run.
-- kittyPid, when given, is the kitty process play runs in: the focused
-- window must belong to it (a second kitty shares the bundle id).
function M.begin(pidPath, kittyPid)
  local win = hs.window.focusedWindow()
  if not win then return "no focused window" end
  if kittyPid and win:application():pid() ~= kittyPid then
    return "the focused window is not this kitty's (pid " .. kittyPid .. ")"
  end
  main = win
  pidFile = pidPath
  savedFrame = main:frame()
  main:setFrame(main:screen():frame(), 0)
  local f = main:frame()
  postMove({x = f.x + f.w * PARK.x, y = f.y + f.h * PARK.y})
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

-- Open each file in `paths` in TextEdit, back to front, and put every window
-- on the right half (kitty takes the left): the windows end up piled on one
-- another, the last one opened on top and focused. One at a time, so the pile
-- is in a known order. stackPlaced() reports when all are in place.
function M.openStack(paths)
  if not main then return "no pinned window" end
  if stackTimer then stackTimer:stop() end
  stackWasRunning = hs.application.get(OTHER_APP) ~= nil
  stackNames, stackWins = {}, {}
  for i, path in ipairs(paths) do stackNames[i] = path:match("[^/]+$") end
  local left, right = halves()
  main:setFrame(left, 0)
  local nextIndex, deadline = 1, 0
  local function launch(i)
    deadline = hs.timer.secondsSinceEpoch() + 5
    -- -F: no restored windows if TextEdit wasn't running
    local args = i == 1 and {"-g", "-F", "-b", OTHER_APP, paths[i]} or {"-g", "-b", OTHER_APP, paths[i]}
    hs.task.new("/usr/bin/open", nil, args):start()
  end
  launch(1)
  stackTimer = hs.timer.doEvery(0.01, function()
    local app = hs.application.get(OTHER_APP)
    for _, win in ipairs(app and app:allWindows() or {}) do
      local t = win:title()
      if t == stackNames[nextIndex] or t == stackNames[nextIndex]:gsub("%.[^.]*$", "") then
        win:setFrame(right, 0)
        win:focus()
        stackWins[nextIndex] = win
        nextIndex = nextIndex + 1
        if nextIndex > #paths then stackTimer:stop(); stackTimer = nil; return end
        launch(nextIndex)
        return
      end
    end
    if hs.timer.secondsSinceEpoch() > deadline then stackTimer:stop(); stackTimer = nil end
  end)
  return "ok"
end

function M.stackPlaced()
  return (#stackNames > 0 and #stackWins == #stackNames) and "ok" or "not yet"
end

-- Close the windows openStack opened (never edited, so no save prompt), and
-- quit TextEdit if it wasn't running before.
function M.closeStack()
  if stackTimer then stackTimer:stop(); stackTimer = nil end
  for _, win in ipairs(stackWins) do win:close() end
  if stackWasRunning == false then
    local app = hs.application.get(OTHER_APP)
    if app then app:kill() end
  end
  stackNames, stackWins, stackWasRunning = {}, {}, nil
  return "ok"
end

-- Arm a 10 ms watcher for a launcher key: once `bundle` is the frontmost app
-- and its focused window's title contains `titlePart`, kitty takes the left
-- half and that window the right. A window that was already open (an Edge
-- window the new tab landed in) has its frame saved for closeTiled.
function M.tileNext(bundle, titlePart)
  if not main then return "no pinned window" end
  if tileTimer then tileTimer:stop() end
  local app = hs.application.get(bundle)
  local before = {}
  for _, w in ipairs(app and app:allWindows() or {}) do before[w:id()] = true end
  tiled = {bundle = bundle, wasRunning = app ~= nil}
  local deadline = hs.timer.secondsSinceEpoch() + 30
  tileTimer = hs.timer.doEvery(0.01, function()
    local front = hs.application.frontmostApplication()
    local win = front and front:bundleID() == bundle and front:focusedWindow()
    if win and win:title():find(titlePart, 1, true) then
      tileTimer:stop(); tileTimer = nil
      local left, right = halves()
      if before[win:id()] then tiled.savedFrame = win:frame() end
      tiled.win = win
      main:setFrame(left, 0)
      win:setFrame(right, 0)
      return
    end
    if hs.timer.secondsSinceEpoch() > deadline then tileTimer:stop(); tileTimer = nil end
  end)
  return "ok"
end

function M.tiledPlaced()
  return (tiled and tiled.win) and "ok" or "not yet"
end

-- Put things back: Edge loses only the demo's tab (Cmd+W; the window may
-- hold the user's tabs) and an existing window gets its frame back; any
-- other app's window is closed. The app quits if the demo started it.
-- Kitty fills the screen and takes focus again.
function M.closeTiled()
  if tileTimer then tileTimer:stop(); tileTimer = nil end
  if not tiled then return "ok" end
  local t = tiled
  tiled = nil
  if t.win then
    if t.bundle == EDGE then
      t.win:focus()
      hs.eventtap.keyStroke({"cmd"}, "w", 20000, hs.application.get(t.bundle))
      if t.savedFrame then
        hs.timer.usleep(200000)
        t.win:setFrame(t.savedFrame, 0)
      end
    else
      t.win:close()
    end
  end
  if not t.wasRunning then
    local app = hs.application.get(t.bundle)
    if app then app:kill() end
  end
  if main then
    main:setFrame(main:screen():frame(), 0)
    main:focus()
  end
  return "ok"
end

-- screencapture -D N records display N: 1 is the main display, then the
-- others. Hammerspoon lists the primary screen first too; the rest are taken
-- to follow in its order, which recordStart checks against the size
-- screencapture actually captures. `display` (DEMO_RECORD_DISPLAY) overrides.
local function displayNumber(screen)
  local primary = hs.screen.primaryScreen():id()
  if screen:id() == primary then return 1 end
  local n = 1
  for _, sc in ipairs(hs.screen.allScreens()) do
    if sc:id() ~= primary then
      n = n + 1
      if sc:id() == screen:id() then return n end
    end
  end
end

-- The pixel size screencapture gets for display n (nil if it can't tell).
local function capturedSize(n)
  local png = os.tmpname() .. ".png"
  hs.execute(string.format("/usr/sbin/screencapture -x -D%d %q", n, png))
  local out = hs.execute(string.format("/usr/bin/sips -g pixelWidth -g pixelHeight %q", png)) or ""
  os.remove(png)
  return tonumber(out:match("pixelWidth: (%d+)")), tonumber(out:match("pixelHeight: (%d+)"))
end

-- Start recording the display the pinned window is on to `path`. Run from
-- here, not from play, so recordStop can interrupt() it: SIGINT is how
-- screencapture finishes its file, and a script's background job would ignore
-- it.
function M.recordStart(path, display)
  if not main then return "no pinned window" end
  if recordTask and recordTask:isRunning() then return "already recording" end
  local screen = main:screen()
  local n = display or displayNumber(screen)
  if not n then return "cannot tell which display kitty is on" end
  -- A wrong guess would record another display: compare the size
  local mode = screen:currentMode()
  local w, h = capturedSize(n)
  if mode and w and h then
    local pw, ph = mode.w * mode.scale, mode.h * mode.scale
    if not ((w == pw and h == ph) or (w == mode.w and h == mode.h)) then
      return string.format("display %d is %dx%d but kitty's display is %dx%d: set DEMO_RECORD_DISPLAY to the right number",
        n, w, h, pw, ph)
    end
  end
  print(string.format("kitty demo: recording display %d of %d", n, #hs.screen.allScreens()))
  recordTask = hs.task.new("/usr/sbin/screencapture", nil, {"-v", "-C", "-D" .. n, path})
  if not recordTask:start() then
    recordTask = nil
    return "screencapture would not start"
  end
  return "ok"
end

function M.recordRunning()
  return (recordTask and recordTask:isRunning()) and "yes" or "no"
end

function M.recordStop()
  if recordTask and recordTask:isRunning() then recordTask:interrupt() end
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
  if pressTimer then pressTimer:stop(); pressTimer = nil end
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
  if pressTimer then pressTimer:stop(); pressTimer = nil end
  if otherTitle then M.closeOther(otherTitle) end
  if stackNames[1] then M.closeStack() end
  if tiled then M.closeTiled() end
  if recordTask then M.recordStop() end
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
