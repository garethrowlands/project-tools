# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Running Tests

```zsh
zsh functions/notes-tests.zsh
zsh functions/project-tests.zsh
zsh functions/sw-tests.zsh
zsh functions/tidy-windows-tests.zsh
zsh functions/window-tests.zsh
zsh config/install-tests.zsh
zsh kitty/demo/tests/demo-tests.zsh
kitty +launch kitty/demo/tests/test_demo_geometry.py
hs -c 'return dofile("'$PWD'/hammerspoon/stack-tests.lua")'   # runs inside Hammerspoon; errors on failure
(cd ../python/tidy-windows-advise && uv run pytest)
```

Each zsh suite exits with code 1 if any test fails. `notes-tests.zsh` has unit tests (temp vault) and integration tests (against `$HOME/notes`). `project-tests.zsh` tests the project picker helpers. `sw-tests.zsh` tests `sw` and its preview (`bin/sw-preview`, against a fake `kitty`) on a temp repo with worktrees. `tidy-windows-tests.zsh` runs `bin/tidy-windows`' apply step against a fake `advise`, `kitty` and `fzf`. `window-tests.zsh` runs `bin/window-list`, `bin/next-agent` and `bin/save-session` against a fake `kitty` and a temp `$HOME` of Claude session files. `tidy-windows-advise`'s pytest suite tests all of its window/git/idle-time/recommendation logic. `kitty/demo`'s suites test the shader demo's geometry, verbs (kitty and Hammerspoon stubbed), card and play; see `kitty/demo/README.md`.

## Architecture

Zsh shell tools for navigating projects and notes. Details are split out by area:

- **[docs/project-picker.md](docs/project-picker.md)** — `functions/project.zsh`, `functions/sw.zsh`, `bin/sw-preview`, `bin/switch-project`, `bin/window`(-list), `bin/next-agent`, `bin/tidy-windows` and `python/tidy-windows-advise/advise`, and how Claude Code session names/titles and agent state (blocked/working/done/idle) are looked up for the window switcher.
- **[docs/notes.md](docs/notes.md)** — `functions/notes-lib.zsh`, `functions/web.zsh`, `bin/web`, `bin/note`: the notes vault (`$HOME/notes`) tooling.
- **[docs/ide-tools.md](docs/ide-tools.md)** — `bin/ide`, `bin/close-project`, `bin/project-web`.
- **`config/`** — files that live under `~/.config` (btop's Catppuccin theme, mdfried's config) plus `install.zsh`, which links them into place and points kitty and btop at the theme (see the `install-scripts` skill). The kitty theme itself is `kitty/themes/catppuccin-mocha-crust.conf`; `zsh/functions/theme.zsh` gives bat and fzf the same palette.
- **`hammerspoon/init.lua`** — Hammerspoon config (symlinked to `~/.hammerspoon/init.lua`): Control+Option+arrow window snapping across monitors, Control+Option+Return to maximize, Control+Option+Command+arrow focus keys, Control+Option+Command+`[`/`]` to step through the stack of windows overlapping the focused one (with a list overlay), and the demo's `demoStage`. Private settings go in untracked `hammerspoon/local.lua`.
- **`hammerspoon/stack.lua`** — the stack selection/cycling logic, free of `hs.*` so it can be tested. Hammerspoon's own directional focus ranks windows by focus recency rather than true z-order, which can pick the wrong window among windows tiled on the same frame; the stack keys use `hs.window.orderedWindows()` instead. Set `focusDebug = true` in `init.lua` to log every arrow-key focus press (candidates and landing window, window titles included) to `~/.hammerspoon/focus-debug.log`.
- **[kitty/demo/README.md](kitty/demo/README.md)** — `kitty/demo/play`: self-running, screen-recordable chapters showing off the kitty setup (1 shaders, 2 windows, panes and tabs, 3 getting around projects) (presenterm deck + director driving kitty via `kitten @` and the mouse via Hammerspoon).

## Kitty key bindings

The overlay-launched pickers (`switch-project`, `window`, `tidy-windows`) plus the misc actions (`ide`, `note`, `project-web`, `next-agent`) are each bound to a key in `kitty.conf`:

```
map kitty_mod+§         launch --type=overlay --cwd=current switch-project
map option+tab          launch --type=overlay --cwd=current window
map kitty_mod+shift+w   launch --type=overlay --cwd=current tidy-windows
map kitty_mod+i         launch --type=overlay --cwd=current ide
map kitty_mod+n         launch --type=overlay --cwd=current note
map kitty_mod+b         launch --type=overlay --cwd=current project-web
map kitty_mod+j         launch --type=overlay --cwd=current next-agent
map kitty_mod+shift+j   launch --type=overlay --cwd=current next-agent --prev
```

`switch-project` and `window` are picker-per-target (jump to one project/window); `tidy-windows` is a bulk review across all open windows — kept as a separate binding rather than merged into `window`, since it fires an Anthropic API call on each run. The same agent states appear as tab markers and desktop notifications without any key, from `kitty/focus_watcher.py` (polls each agent's state) and `kitty/tab_bar.py` (`{custom}` in `tab_title_template`); see `docs/project-picker.md`. `next-agent` has no picker: it focuses the next window whose Claude agent is blocked or has finished unseen (which needs `watcher focus_watcher.py` in `kitty.conf`), or with none of those just the next agent window; `--prev` goes backwards. See `.claude/skills/install-scripts/SKILL.md` for the full setup (symlinks, `listen_on` for `window`'s live preview, these bindings).

## Dependencies

`rg` (ripgrep), `fd`, `fzf`, `bat`, `jq`, `awk`, `kitty` (optional). `bin/tidy-windows` additionally needs `uv` (runs `../python/tidy-windows-advise/advise`) and `ANTHROPIC_API_KEY` set (falls back to keep-only recommendations without it).
