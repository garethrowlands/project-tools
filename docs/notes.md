# Notes

**`functions/notes-lib.zsh`** — core library for the notes vault (`$HOME/notes`), Markdown files with YAML frontmatter:
- `_notes_extract_titles` — `rg` + `awk` parses `title:` fields (inline, quoted, `>-` block scalar, flow-wrapped). Outputs `filepath<TAB>T<TAB>title`.
- `_notes_extract_excerpts` — extracts `> ## Excerpt` / `> ->` blocks. Outputs `filepath<TAB>E<TAB>excerpt`.
- `_notes_picker` — fzf picker with Title/Body modes toggled via `ctrl-r`, using sentinel strings to avoid subshells.

**`functions/web.zsh`** — exposes `web <query>` (opens source URL) and `note <query>` (opens note file), both with kitty tab support via FIFO.

**`bin/web`** / **`bin/note`** — standalone kitty-launchable counterparts to the `web`/`note` functions above, intended for a kitty key binding (`launch --type=overlay`). Switch to `stack` layout, run `_notes_picker` directly, restore the previous layout, then act on the result: `bin/web` extracts the `source`/`url` frontmatter field and `open`s it in the browser; `bin/note` opens the picked note in `$EDITOR`. Unlike the `web`/`note` functions, these open the result directly rather than printing an OSC 8 hyperlink.

## Conventions

- `_notes_picker` avoids subshells for mode-switching via sentinel strings from `fzf --bind become(…)`.
