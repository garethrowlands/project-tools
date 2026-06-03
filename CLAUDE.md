# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Running Tests

```zsh
zsh functions/notes-tests.zsh
zsh functions/project-tests.zsh
```

Each exits with code 1 if any test fails. `notes-tests.zsh` has unit tests (temp vault) and integration tests (against `$HOME/notes`). `project-tests.zsh` tests the project picker helpers.

## Architecture

Zsh shell tools for navigating projects and notes.

### Project picker

**`functions/project.zsh`** — interactive git project picker. Source this to get `project` and `current-project`.

- `project [query]` — opens an fzf picker over all git repos found under `$PROJECT_ROOTS`. Key bindings: `enter` focuses or opens the project, `ctrl-t` opens in a new kitty tab, `ctrl-i` opens the IDE, `ctrl-w` closes the project IDE, `ctrl-y` copies the path. Projects with open kitty windows are shown first (prefixed with `*`) in an _Open_ group; the rest appear under _All_. Preview pane shows open kitty windows then README/CLAUDE.md/ls.
- `current-project` — prints the git root of `$PWD`.
- `_project_build_list` — builds the tab-delimited `PATH<TAB>LABEL` list (with group headers) fed to fzf. Open projects detected from kitty CWDs.
- `_project_preview_dir` — preview command: shows open kitty windows for the project (bold, with divider), then `bat` output of README/CLAUDE.md or `ls`.
- `_project_preview_windows` — reads pre-fetched `kitty @ ls` JSON from a temp file, returns bold-formatted window list for a given project path.
- `_project_picker` — runs fzf with all bindings; pre-fetches `kitty @ ls` once at startup into a temp file to avoid hangs in preview subprocesses.
- `_project_scan` — scans `$PROJECT_ROOTS` for git repos using `fd`, writes to cache file.

When run from a kitty key binding (no tty), `project` launches a new kitty tab for the picker and returns the result via a named FIFO.

**`bin/switch-project`** — intended to be bound to a kitty key binding (`launch --type=overlay`). Switches to `stack` layout for full-screen display, runs `project --new-tab-key`, then restores the previous layout via `kitten @ last-used-layout`. Focuses the matching kitty window by CWD, or opens a new window/tab.

**`bin/window`** — `fzf` picker over all open kitty windows; focuses the selected one. Switches to `stack` layout for full-screen display and restores the previous layout on exit. Preview pane shows the live screen content of the highlighted window via `kitty @ get-text --extent=screen --ansi`, with trailing spaces and SGR codes stripped by `perl`. Requires `listen_on` in `kitty.conf` so that `KITTY_LISTEN_ON` is inherited by fzf preview subprocesses (tty-based remote control blocks in subprocesses). Key binding: `ctrl-t` moves the selected window to a new tab.

### IDE tools

**`bin/ide`** — opens the appropriate IDE (VS Code or IntelliJ IDEA) for the git root of a given path or file (or `$PWD`). Detects the IDE from project files (`pom.xml`, `.idea`, `.vscode`, etc.).

**`bin/close-project`** — inverse of `ide`: closes the IDE window for a given project path (or `$PWD`). When called with no argument, also closes the current kitty pane. Uses `System Events` + close-button click for VS Code (no AppleScript dictionary).

### Notes

**`functions/notes-lib.zsh`** — core library for the notes vault (`$HOME/notes`), Markdown files with YAML frontmatter:
- `_notes_extract_titles` — `rg` + `awk` parses `title:` fields (inline, quoted, `>-` block scalar, flow-wrapped). Outputs `filepath<TAB>T<TAB>title`.
- `_notes_extract_excerpts` — extracts `> ## Excerpt` / `> ->` blocks. Outputs `filepath<TAB>E<TAB>excerpt`.
- `_notes_picker` — fzf picker with Title/Body modes toggled via `ctrl-r`, using sentinel strings to avoid subshells.

**`functions/web.zsh`** — exposes `web <query>` (opens source URL) and `note <query>` (opens note file), both with kitty tab support via FIFO.

## Key Conventions

- `_project_build_list` uses BSD awk with roots and CWDs fed via process substitution (separated by `---` sentinel) to avoid newline-in-`-v` issues.
- `kitty @ ls` JSON is pre-fetched once at picker startup and written to a temp file; preview subprocesses read the file rather than calling `kitty @`. With tty-based remote control (no `listen_on`), `kitty @` blocks in subprocesses; with `listen_on` configured (socket-based), `KITTY_LISTEN_ON` is inherited and `kitty @` works in subprocesses — `bin/window` relies on this for its live preview.
- `null` CWDs in kitty ls JSON are guarded with `// empty` before `startswith()` to avoid jq type errors.
- `FZF_PREVIEW_COLUMNS` (not `$COLUMNS`) is used for preview pane width — fzf sets it in the preview subprocess.
- `_notes_picker` avoids subshells for mode-switching via sentinel strings from `fzf --bind become(…)`.

## Installation

Symlink the executables onto your PATH:

```zsh
ln -s $PWD/zsh/bin/ide ~/.local/bin/ide
ln -s $PWD/zsh/bin/close-project ~/.local/bin/close-project
ln -s $PWD/zsh/bin/switch-project ~/.local/bin/switch-project
ln -s $PWD/zsh/bin/window ~/.local/bin/window
```

Kitty key binding example:

```
map kitty_mod+§ launch --type=overlay --cwd=current switch-project
```

## Dependencies

`rg` (ripgrep), `fd`, `fzf`, `bat`, `jq`, `awk`, `kitty` (optional).
