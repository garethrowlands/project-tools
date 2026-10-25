# Pointer Follows Keyboard Focus Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When focus moves by keyboard (Hammerspoon keys, Contexts, Cmd+Tab), the mouse pointer moves with it; mouse-driven focus changes never move it.

**Architecture:** A pure module `hammerspoon/pointer.lua` (no `hs.*`, like `stack.lua`) holds the decisions: where the pointer goes, what spot to remember, whether a focus change was a keyboard switch. A thin wiring module `hammerspoon/pointer-follow.lua` feeds it Hammerspoon events and performs the move. A spike (Task 1) measures real event timing with Contexts first and fixes the mechanism and timing values.

**Tech Stack:** Lua, Hammerspoon (`hs.eventtap`, `hs.window.filter` / `hs.application.watcher` / `hs.axuielement`, `hs.mouse`); tests run inside Hammerspoon via `hs -c`, in the style of `hammerspoon/stack-tests.lua`.

**Spec:** `docs/superpowers/specs/2026-10-25-pointer-follows-focus-design.md`

## Global Constraints

- Pointer moves only when a window gains focus and a key event preceded it; a mouse click or pointer movement after the last key event cancels this.
- Destination order: remembered spot, else stay if already inside the window, else nearest point inside the frame inset by a small margin. Never the window centre (except a frame too small for the inset).
- Remembered spot: one per window id, stored as an offset from the window's top-left, in memory only, recorded on any focus loss only if the window is topmost at the pointer; forgotten when the window closes; ignored if outside the frame or off every screen.
- Standard, visible windows only. No per-app special cases.
- Existing Hammerspoon focus/stack keys keep working unchanged; no explicit warp in them unless the spike shows a missing focus event.
- Logic in a module free of `hs.*`.

## Review Focus

1. A window smaller than twice the inset: destination is a sensible point, not off the window (Task 2).
2. A spot saved on a display that is now gone: ignored, falls through (Task 2).
3. The pointer sits over a window that covers the departing one: no spot recorded (Task 2).
4. Cmd+Tab opens Contexts, then the user clicks an entry: no move (Task 3).
5. Our own warp emits a mouse-moved event: it must not cancel the keyboard evidence for the next switch (Task 4 checks).

---

### Task 1: Spike (gate): measure events and pick the mechanism

Throwaway: the script is deleted at the end. Needs the user at the machine with Contexts.

**Files:**
- Create then delete: `hammerspoon/spike-pointer.lua`
- Modify: `docs/superpowers/specs/2026-10-25-pointer-follows-focus-design.md` (append a "Spike results" section)

**Produces:** a "Spike results" section giving: chosen focus mechanism; the keyboard-evidence window in seconds (`window`); whether a posted mouse-moved event is needed for hover; whether the stack keys and focus keys produce a focus event every time.

- [ ] **Step 1:** Write `hammerspoon/spike-pointer.lua` that prints to the Hammerspoon console one timestamped line (`hs.timer.secondsSinceEpoch()`) for each of: `keyDown`, `flagsChanged` (with the flags), mouse down / `mouseMoved`, `hs.application.watcher` activation, `hs.window.filter` `windowFocused`, and an `hs.axuielement` observer on `AXFocusedWindowChanged` for the frontmost app.
- [ ] **Step 2:** Load it (`hs -c 'dofile("<repo>/hammerspoon/spike-pointer.lua")'`) and have the user do each of these while you read the console: a Hammerspoon focus key; the stack keys, including on an already-focused or same-app window; Contexts via Cmd+Tab (note whether focus changes on Tab down or on Cmd release); plain Cmd+Tab; clicking a window; Cmd+Tab then clicking a Contexts entry.
- [ ] **Step 3:** Record, for each mechanism, key-to-focus delay. Pick the one that fires for every case above with no visible lag; prefer `hs.window.filter`, fall back to `hs.application.watcher` + AX. Choose `window` as the largest observed delay plus margin (default guess 0.5s, replaced by the measurement).
- [ ] **Step 4:** Test the move: with the pointer over another window, call `hs.mouse.absolutePosition({x=..,y=..})` onto a hoverable element in Teams and in a browser and have the user say if hover updates. If not, try posting an `hs.eventtap.event.newMouseEvent(hs.eventtap.event.types.mouseMoved, pt):post()` after the move and re-check.
- [ ] **Step 5:** Append "Spike results" to the spec with the four outputs above, delete `hammerspoon/spike-pointer.lua`, commit the spec change.

---

### Task 2: Geometry decisions in `pointer.lua`

**Files:**
- Create: `hammerspoon/pointer.lua`
- Create: `hammerspoon/pointer-tests.lua`
- Modify: `CLAUDE.md` (add `hs -c 'return dofile("'$PWD'/hammerspoon/pointer-tests.lua")'` to the "Running Tests" block)

**Interfaces:**
- Produces (a point is `{x, y}`, a frame is `{x, y, w, h}`):
  - `M.destination(pt, frame, spot, opts) -> point|nil`: where to move the pointer, or nil to leave it. `spot` is an offset `{x, y}` or nil; `opts.inset` (default 12), `opts.screens` (list of frames, optional; nil means no screen check).
  - `M.record(pt, frame, topmostId, windowId) -> offset|nil`: the spot to remember for a departing window, nil if none.
  - `M.topmostAt(items, pt) -> id|nil`: items are front-to-back `{id, frame}`; the id of the first whose frame contains `pt`.

- [ ] **Step 1: Write the failing tests** in `pointer-tests.lua` (same header, `check` helper and `dofile` of `pointer.lua` as `stack-tests.lua`), with frame `F = {x=100,y=100,w=800,h=600}`:
  - remembered spot wins: `destination({x=0,y=0}, F, {x=50,y=40})` is `{x=150,y=140}`.
  - spot outside frame ignored: `destination({x=500,y=300}, F, {x=900,y=40})` is nil (pointer inside, falls through).
  - spot on a gone display ignored (Review Focus 2): `destination({x=0,y=0}, {x=900,y=0,w=800,h=600}, {x=500,y=10}, {screens={{x=0,y=0,w=1000,h=800}}})` is the nearest point `{x=912,y=12}`, not the spot.
  - pointer inside, no spot: nil.
  - nearest point: pointer `{x=0,y=300}` gives `{x=112,y=300}`; `{x=0,y=0}` gives `{x=112,y=112}`; `{x=2000,y=2000}` gives `{x=888,y=688}`.
  - tiny window (Review Focus 1): `destination({x=500,y=500}, {x=0,y=0,w=10,h=10}, nil)` is `{x=5,y=5}`.
  - `record` inside and topmost gives `{x=pt.x-F.x, y=pt.y-F.y}`; outside gives nil; inside but `topmostId ~= windowId` gives nil (Review Focus 3).
  - `topmostAt` returns the first containing item's id, nil when none contains the point.
- [ ] **Step 2: Run to verify it fails:** `hs -c 'return dofile("'$PWD'/hammerspoon/pointer-tests.lua")'`; expected error: `pointer.lua` missing.
- [ ] **Step 3: Implement** the three functions in `hammerspoon/pointer.lua`. A point is inside a frame when `x >= f.x and x < f.x + f.w` (same for y). Nearest point is the pointer clamped into the frame shrunk by `inset` on each side; on an axis where the frame is under `2 * inset`, use that axis's midpoint. A spot is valid only if its absolute point is inside the frame and (if `opts.screens`) inside some screen frame.
- [ ] **Step 4: Run the tests;** expected: a summary line, no error.
- [ ] **Step 5: Commit** `hammerspoon/pointer.lua`, `hammerspoon/pointer-tests.lua`, `CLAUDE.md`.

---

### Task 3: Keyboard-evidence tracker in `pointer.lua`

**Files:**
- Modify: `hammerspoon/pointer.lua`, `hammerspoon/pointer-tests.lua`

**Interfaces:**
- Produces (all times are seconds, passed in, no clock inside):
  - `M.newEvidence(window) -> state`: `window` is the Task 1 value (default 0.5).
  - `M.noteKey(state, now)`: a key-down or modifier change.
  - `M.noteModifiers(state, held)`: `held` true while any modifier is down. A change also counts as `noteKey` at the caller's time, so call both from a `flagsChanged` handler.
  - `M.noteMouse(state, now)`: a click, scroll or pointer movement not made by us.
  - `M.isKeyboardSwitch(state, now) -> boolean`.

- [ ] **Step 1: Write the failing tests** (a fresh state per case):
  - no events: false.
  - key at 0: true at 0.3, false at 0.6 (window 0.5).
  - modifier held keeps it true: `noteKey(0)`, `noteModifiers(true)`, true at 2.0; after `noteKey(2.1)` and `noteModifiers(false)`, true at 2.2 (the release is itself a key event).
  - mouse after key cancels (Review Focus 4): key 0, mouse 0.1, false at 0.2; and with the modifier still held, key 0, `noteModifiers(true)`, mouse 1.0, false at 1.1.
  - key after mouse counts: mouse 0, key 0.1, true at 0.2.
- [ ] **Step 2: Run to verify it fails;** expected: `newEvidence` is nil.
- [ ] **Step 3: Implement** the state as a table of `lastKey`, `lastMouse`, `held`, `window`. `isKeyboardSwitch` is true when a key event exists, no mouse event is later than it, and either `now - lastKey <= window` or a modifier is held.
- [ ] **Step 4: Run the tests;** expected: summary line.
- [ ] **Step 5: Commit** both files.

---

### Task 4: Wire it into Hammerspoon

**Files:**
- Create: `hammerspoon/pointer-follow.lua`
- Modify: `hammerspoon/init.lua` (append: `dofile(<dir of init.lua> .. "/pointer-follow.lua").start()`, using the same directory lookup as the `stack.lua` line)
- Modify: `CLAUDE.md` (add a bullet for `pointer.lua` / `pointer-follow.lua` next to the `stack.lua` bullet)

**Interfaces:**
- Consumes: Task 2 and 3 functions; the mechanism, `window` and hover answer from the Task 1 "Spike results".
- Produces: `M.start(opts)` with `opts.debug` (when true, `print` each decision to the Hammerspoon console).

- [ ] **Step 1: Implement `start`:**
  - An `hs.eventtap` on `keyDown`, `flagsChanged`, `leftMouseDown`, `rightMouseDown`, `otherMouseDown`, `scrollWheel`, `mouseMoved` feeding the Task 3 state. Ignore `mouseMoved` for 0.1s after our own move.
  - A focus observer (mechanism from the spike) restricted to standard, visible windows. On a focus change from window P to window N: record P's spot (`hs.mouse.absolutePosition()`, `topmostAt` over `hs.window.orderedWindows()` as `stackItems` in `init.lua` does, `record`) into a table keyed by window id; then if `isKeyboardSwitch`, compute `destination` for N (screens from `hs.screen.allScreens()` frames) and move the pointer, posting a mouse-moved event too if the spike said so.
  - Delete a window's spot when it is destroyed. Tolerate a nil previous window or nil id.
- [ ] **Step 2:** Reload with `hs -c 'hs.reload()'`, and confirm the Hammerspoon console shows no error.
- [ ] **Step 3: Manual verification with the user, `debug = true`.** Each must behave as stated:
  1. Focus key to a window the pointer is not over, no history: pointer lands just inside its edge, nearest to where it was.
  2. Click in window A, focus-key to B, focus-key back to A: pointer returns to the clicked spot in A.
  3. Contexts (Cmd+Tab) to a window on another screen: pointer follows.
  4. Cmd+Tab then click a Contexts entry: pointer stays where clicked.
  5. Click a window to focus it: pointer does not move.
  6. A background app steals focus, or the focused window closes: pointer does not move, no console error.
  7. Two keyboard switches in quick succession (our own move must not cancel the second): the pointer follows both times.
  8. Stack keys `]` and `[` between overlapping windows: pointer follows, or per the spike, the stack-key gap is handled.
- [ ] **Step 4:** Run `hs -c 'return dofile("'$PWD'/hammerspoon/stack-tests.lua")'` and the pointer tests; both pass.
- [ ] **Step 5: Commit** `hammerspoon/pointer-follow.lua`, `hammerspoon/init.lua`, `CLAUDE.md`.
