# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Running Tests

```zsh
zsh functions/notes-tests.zsh
zsh functions/project-tests.zsh
zsh functions/sw-tests.zsh
zsh kitty/demo/tests/demo-tests.zsh
kitty +launch kitty/demo/tests/test_demo_geometry.py
(cd ../python/tidy-windows-advise && uv run pytest)
```

Each zsh suite exits with code 1 if any test fails. `notes-tests.zsh` has unit tests (temp vault) and integration tests (against `$HOME/notes`). `project-tests.zsh` tests the project picker helpers. `sw-tests.zsh` tests `sw` against a temp repo with worktrees. `tidy-windows-advise`'s pytest suite tests all of its window/git/idle-time/recommendation logic. `kitty/demo`'s suites test the shader demo's geometry, verbs (kitty and Hammerspoon stubbed), card and play; see `kitty/demo/README.md`.

## Architecture

Zsh shell tools for navigating projects and notes. Details are split out by area:

- **[docs/project-picker.md](docs/project-picker.md)** — `functions/project.zsh`, `functions/sw.zsh`, `bin/switch-project`, `bin/window`(-list), `bin/tidy-windows` and `python/tidy-windows-advise/advise`, and how Claude Code session names/titles are looked up for the window switcher.
- **[docs/notes.md](docs/notes.md)** — `functions/notes-lib.zsh`, `functions/web.zsh`, `bin/web`, `bin/note`: the notes vault (`$HOME/notes`) tooling.
- **[docs/ide-tools.md](docs/ide-tools.md)** — `bin/ide`, `bin/close-project`, `bin/project-web`.
- **[kitty/demo/README.md](kitty/demo/README.md)** — `kitty/demo/play`: self-running, screen-recordable chapters showing off the kitty setup (1 shaders, 2 windows, panes and tabs) (presenterm deck + director driving kitty via `kitten @` and the mouse via Hammerspoon).

## Kitty key bindings

The overlay-launched pickers (`switch-project`, `window`, `tidy-windows`) plus the misc project actions (`ide`, `note`, `project-web`) are each bound to a key in `kitty.conf`:

```
map kitty_mod+§         launch --type=overlay --cwd=current switch-project
map option+tab          launch --type=overlay --cwd=current window
map kitty_mod+shift+w   launch --type=overlay --cwd=current tidy-windows
map kitty_mod+i         launch --type=overlay --cwd=current ide
map kitty_mod+n         launch --type=overlay --cwd=current note
map kitty_mod+b         launch --type=overlay --cwd=current project-web
```

`switch-project` and `window` are picker-per-target (jump to one project/window); `tidy-windows` is a bulk review across all open windows — kept as a separate binding rather than merged into `window`, since it fires an Anthropic API call on each run. See `.claude/skills/install-scripts/SKILL.md` for the full setup (symlinks, `listen_on` for `window`'s live preview, these bindings).

## Dependencies

`rg` (ripgrep), `fd`, `fzf`, `bat`, `jq`, `awk`, `kitty` (optional). `bin/tidy-windows` additionally needs `uv` (runs `../python/tidy-windows-advise/advise`) and `ANTHROPIC_API_KEY` set (falls back to keep-only recommendations without it).
