# Pointer follows keyboard focus: design

## Intent and why

When focus is moved with the keyboard, the mouse pointer stays where it was, usually over the window just left. Keyboard-driven windows like kitty don't care, but many apps (Teams, Outlook, browsers) are awkward without the mouse. To use the mouse in the new window, the user must reach for the trackpad and drag the pointer across, at which point they could have clicked the window to focus it and skipped the keyboard.

Goal: when focus moves by keyboard, the pointer moves with it, so the user can use the mouse in the new window without first travelling to it.

## Principle

The pointer may move on its own **only when the user's hands are on the keyboard** and not driving the pointer. Switching focus with a keyboard shortcut takes both hands, so a keyboard switch implies the trackpad is untouched. Any switch the user makes with the mouse or trackpad never moves the pointer.

## Behaviour

### When the pointer moves

A window gains focus and a key press happened shortly before it. This covers, with no special cases:

- the Hammerspoon focus keys (Control+Option+Command+arrows) and the stack keys (Control+Option+Command+`[` / `]`);
- Contexts (the user's window switcher, bound to Cmd+Tab) and plain Cmd+Tab. These bypass Hammerspoon's key handlers, so the feature must work by observing focus changes, not by hooking Hammerspoon's own keys.

The pointer does **not** move when:

- the user clicked to focus (including clicking an entry in Contexts' list: the user is driving the pointer). A mouse click or pointer movement after the last key press cancels the keyboard evidence: the user opens Contexts with Cmd+Tab (a key press) and then clicks an entry, and that must not move the pointer;
- focus changed with no preceding key press (an app stealing focus, a notification, a window closing and focus falling to another). Default is to leave the pointer alone; positive evidence of a keyboard switch is required.

### Where it goes (in order)

1. The window's remembered spot, if it has one.
2. Otherwise, if the pointer is already inside the window, it stays.
3. Otherwise, the nearest point inside the window to the pointer's current position, inset by a small margin so it avoids title-bar buttons and resize edges. Works across screens, since the user often doesn't know where Contexts will bring the window up.

The centre of the window is deliberately not used (arbitrary).

### What is remembered

When a window loses focus, by any route (keyboard, mouse, Contexts), record the pointer position **relative to that window** if and only if the pointer is inside it. If the pointer is over another window, record nothing and keep any earlier spot. Relative storage means the spot still makes sense after the window is moved or resized.

One spot per window, overwritten each time. Spots do not expire.

## Goals, non-goals, anti-goals

Goals: the above; works the same for every app and every keyboard route.

Non-goals (decided for now, may revisit):
- Recording the last click in a window as the remembered spot (considered; the pointer position on leaving was preferred as more faithful to "where I was").
- Expiring or invalidating stale spots after a time or large resize/move.
- Any per-app special cases or exclusions (e.g. for kitty). The user does not want rules to remember.

Anti-goals: the pointer must never move while the user is using the mouse or trackpad, and must never move on focus changes the user didn't cause.

## Constraints

- Lives in the Hammerspoon config (`hammerspoon/init.lua`, symlinked to `~/.hammerspoon/init.lua`). Follow the pattern of `hammerspoon/stack.lua`: put the decision logic in a module free of `hs.*` so it can be unit-tested, with tests in the style of `hammerspoon/stack-tests.lua`.
- Must coexist with the existing focus and stack keys and with `focusDebug`.

## Left to the builder

- How to observe focus changes and recent key presses in Hammerspoon (e.g. `hs.window.filter` or `hs.application.watcher`, plus an `hs.eventtap` on key events), and how recent "shortly before" must be. Cmd+Tab style switchers may change focus on modifier release, so the window must cover that. This is the main technical risk and is worth a quick spike on the real machine with Contexts.
- The inset margin, and the exact timing window.
- Latency of the focus observer: the spike must measure the delay from key press to the focus event, with Contexts, on the real machine, and choose the mechanism from the result. Candidates are `hs.application.watcher`, `hs.window.filter` (which may add small internal delays), or observing the focused-window-changed accessibility notification directly with `hs.axuielement`. The pointer should not visibly jump after the new window appears. The timing window must be wide enough to cover the observed lag.
- Pointer position at the moment of focus loss: by the time the loss event arrives it may already have moved (e.g. with a mouse click); the rule "record only if inside the departing window" is the safeguard, but the builder should check what is observable.
- Whether any debug logging is useful, in the style of `focusDebug`.

## Calls made by the author, not yet confirmed

- One remembered spot per window (not a history), keyed by window id, held in memory only. Losing spots on a Hammerspoon reload is fine. Forget a window's spot when it closes.
- Spot recorded on any focus loss, not only keyboard departures (the user agreed once Contexts was in the picture).
- Keyboard evidence: a key-down or a modifier change (`flagsChanged`) counts, and a modifier still held counts, because Cmd+Tab-style switchers may change focus on modifier release. A click or pointer movement after the last key event cancels it. Exact timing is for the spike to settle. **The spike is a gate:** do it first, on the real machine with Contexts, before planning the rest.
- "Inside the window" for recording a spot means the topmost window at the pointer is that window (hit-test with `hs.window.orderedWindows()`, as `stack.lua` does), not just frame containment. On arrival the new window is raised, so frame containment is enough for the stay-put rule.
- A remembered spot that now falls outside the window's frame, or off every screen, is ignored and the rules fall through to stay-put or nearest point.
- Applies to standard, visible windows only. Ignore the desktop, Spotlight, panels, palettes and popups. Windows on other Spaces count like any other; the nearest-point rule handles a window on another screen.
- One observer is the single mechanism. The Hammerspoon focus and stack keys are not given their own warp, unless the spike shows a key (e.g. focusing an already-focused window, or one in the same app) produces no focus event. In that case that key calls the same warp function.
- The warp should make hover states update in Teams, Outlook and browsers, so post a real mouse-moved event if a bare `hs.mouse.absolutePosition` doesn't. Check in the spike.

## Changes after live use and review

- A focus event for the window that already has focus is ignored, and one key press justifies at most one move (found when the pointer jumped to a remembered spot after the user clicked inside Outlook).
- Plain key presses count as keyboard evidence (switchers like Contexts are driven with unmodified keys); a modifier change counts only for cmd, ctrl and alt.
- Releasing a modifier does not override a mouse action made since the last key event. A click inside the window that just gained focus, within 1s, makes the switch a mouse switch whatever keys followed.
- On a keyboard switch, the departing window's spot is recorded with the incoming window left out of the "topmost at the pointer" check, since the incoming window is already raised and may cover the pointer.
- Known trade-off, not fixed: because plain keys count for 0.5s, a window that steals focus while the user is typing (or Cmd+W handing focus to another window) moves the pointer. Shortening the window for plain keys would need a measurement of the key-to-focus lag first; the debug log prints it.
