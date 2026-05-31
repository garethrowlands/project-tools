# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Running Tests

```zsh
zsh functions/notes-tests.zsh
```

The test runner exits with code 1 if any test fails. Tests are split into unit tests (against a temp vault) and integration tests (against `$HOME/notes`).

## Architecture

This repo contains zsh shell functions for searching and navigating a personal notes vault (`$HOME/notes`), where notes are Markdown files with YAML frontmatter.

**`functions/notes-lib.zsh`** — the core library. Key functions:
- `_notes_extract_titles` — uses `rg` + `awk` to parse YAML frontmatter `title:` fields, handling inline, quoted, `>-` block scalar, and flow-wrapped multi-line forms. Outputs `filepath<TAB>T<TAB>title`.
- `_notes_extract_excerpts` — extracts `> ## Excerpt` / `> ->` convention from note bodies. Outputs `filepath<TAB>E<TAB>excerpt`.
- `_notes_title_list` — joins titles + excerpts; only includes notes with a `title:` field.
- `_notes_all_list` — same but falls back to basename for untitled notes.
- `_notes_title_map_file` — writes a temp `filepath<TAB>title` file for use as an `awk` join table in `fzf` reload commands. **Caller must `rm -f` the returned path.**
- `_notes_picker` — interactive `fzf` picker with two modes (Title / Body search), toggled via `ctrl-r`. Uses sentinels (`§body§…`, `§title§…`) returned from `fzf --bind become(…)` to signal mode switches without subshells.

**`functions/web.zsh`** — sources `notes-lib.zsh` and exposes two user-facing commands:
- `web <query>` — picks a note, extracts its `source:`/`url:` field, and prints an OSC 8 hyperlink (or plain URL when not a terminal).
- `note <query>` — picks a note and prints an OSC 8 file:// hyperlink to the note path.

Both commands support **kitty terminal**: when running inside kitty with socket access, they open a new tab for the interactive picker and communicate the result back via a named pipe (FIFO).

## Key Conventions

- Notes frontmatter is parsed with `rg` + `awk`, not a YAML library — the awk handles the specific YAML subset used in this vault.
- `_notes_picker` avoids subshells for mode-switching by having `fzf` print sentinel strings that the outer `while true` loop interprets.
- The `awk` join pattern (`NR==FNR{…;next}{…}`) is used to attach titles to file paths in `fzf` reload commands, where the map file path is embedded in the reload string at construction time.

## Dependencies

`rg` (ripgrep), `fd`, `fzf`, `bat`, `jq`, `awk`, `kitty` (optional).
