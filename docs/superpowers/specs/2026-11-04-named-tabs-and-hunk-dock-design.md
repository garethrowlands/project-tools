# Named project tabs and the Hunk dock

Uses two groups of kitty 0.50.0 features. Everything below was tried in a scratch
kitty before it was written down.

## 1. Project tabs are found by name, and kept alphabetical

A project's tab is the tab titled `_project_tab_name <path>` (the main worktree's
directory name). `switch-project` in new-tab mode used to hunt for a window by cwd,
count the windows in its tab, `detach-window --target-tab new`, re-run `kitty @ ls`
to find the new tab and `set-tab-title` it. It now asks kitty for the tab by name:

- **No window in the project yet:**
  `launch --type=tab --tab-title=NAME --location=by-title --focus-existing=@title --cwd=PATH`
  Focuses the project's tab if it exists, otherwise opens it in its alphabetical place.
- **A window already open in the project (matched by cwd):**
  `detach-window --match=id:W --target-tab=@title --tab-title=NAME --location=by-title --create-if-missing`
  followed by `focus-window`. Moves the window to the project's tab, creating it
  (alphabetically placed) if needed. If the window is already in the tab titled NAME it
  is only focused.

Verified behaviour this relies on: `@title` matching is exact (no prefix or regex
surprises, so `a.b` ≠ `axb`, `c++` works), it matches a tab whatever its title came from,
an explicit `--tab-title` survives a program setting its own title, and `by-title` orders
tabs alphabetically *including* tabs that were not created that way (they sort by their
current title). Tab order is therefore alphabetical for every tab; this is the thing to
revisit if chronological order turns out to be missed.

`window`'s `ctrl-t` uses the same function. `tidy-windows`' apply step sends `new:<project>`
moves to the named tab the same way (`--stay-in-tab` keeps you where you were); moves to a
tab `advise` chose by id are unchanged, since such a tab may be untitled.

Out of scope for now: `ide`/`note`/`project-web`.

## 2. `hunk-dock`: Hunk review in a top window-dock

`bin/hunk-dock [--close] [DIR]` opens (or closes) Hunk for a repo in a window-dock.

- Defaults: `DIR` is the cwd; the dock is attached to the tab holding the caller's window
  (`$KITTY_WINDOW_ID`; `launch --match=window_id:ID` picks the tab), top edge, 65%, no
  focus taken, titled `hunk`, running `hunk diff --watch` in `DIR`. Override with
  `HUNK_DOCK_EDGE` / `HUNK_DOCK_SIZE`.
- Idempotent: if a window titled `hunk` with cwd `DIR` already exists, nothing is
  launched (its id is printed).
- `--close` closes that window. Docks can't be resized after launch, so resizing is
  close, set `HUNK_DOCK_SIZE`, reopen.
- A window-dock is saved in sessions with its options and closes with its host window, so
  `save-session` and `restore.kitty-session` need no change.
- No key binding (the user prefers asking Claude); Claude runs `hunk-dock` instead of
  composing the `kitten @ launch` line, then drives Hunk with `hunk-review`.

## 3. `btop-dock`: btop in a bottom tab-dock

`bin/btop-dock [--close]`, the same shape as `hunk-dock` but a `tab-dock`: bottom edge,
25% of the tab, `--dock-skip-focus` (display-only, so `--close` removes it), titled `btop`,
running `btop -c <copy of the user's btop.conf with shown_boxes = "cpu">` (btop with its four
boxes needs 24 rows and will not draw in a 25% strip; `BTOP_DOCK_BOXES` overrides). Idempotent per tab (a `btop` window in the calling window's tab), not per
repo. `BTOP_DOCK_EDGE` / `BTOP_DOCK_SIZE` override. Closes with the tab's last real window.
