# kitty link handling

Files in `kitty/`, installed by symlinking them into `~/.config/kitty/` (see the
`install-scripts` skill). Built against kitty 0.49.1 and eza 0.23.4; kitty's
kitten APIs are internal and may change between versions.

## What it does

Clicking a local `file://` link (from `eza --hyperlink`, `rg --hyperlink-format=kitty`, `fd --hyperlink`, ...) opens it in a TUI, never a GUI app:

| Link | Opens |
|---|---|
| directory, pane's zsh idle at a prompt | `cd` in that shell (typed command kept) |
| directory, anything else running | `yazi` overlay at that directory |
| `file#LINE` | `micro file +LINE` overlay |
| Markdown | `glow --tui` overlay; `e` edits in `$EDITOR`, `o` opens the note in Obsidian if it is inside a vault |
| other text (sniffed: UTF-8, no NULs) | `micro` overlay |
| anything else | `yazi` overlay with the file selected |

Overlays cover the clicked pane, start in its directory and copy its environment. `https://` and other non-file links are untouched.

`Cmd+click` opens links on release, skipping kitty's ~0.5s wait for a possible double click. `Cmd+P` shows a menu of hint modes (over a dimmed copy of the pane) instead of silently waiting for a second key:

| Key | Does |
|---|---|
| `p` / `m` | insert the path of one / several files listed with hyperlinks, quoted for the shell, relative to its directory |
| `f` | insert a file path found in plain text |
| `o` | open a file path found in text (through the click rules above) |
| `w` `l` `h` | insert a word / line / hash |
| `n` | open `file:line` in `micro` at that line |
| `y` | open a hyperlink |
| `c` `d` | kitty's file / directory chooser |

## Files

- **`open-actions.conf`** — one rule: every `file:` link goes to `open_local.py`.
- **`open_local.py`** — no-UI kitten that decides what a click does. Rebuilds the path from the raw URL because eza does not percent-encode `#`, `?` or `%` in names (so kitty would otherwise split `12#frag` at the `#`).
- **`kitty-cd-link.zsh`** — sourced from `.zshrc`. The zsh side of click-to-cd, plus publishing `$EDITOR` to kitty.
- **`hint_menu.py`** — the `Cmd+P` menu.
- **`links.conf`** — `include`d at the end of `kitty.conf`: the `Cmd+click`, glow `o` and `Cmd+P` mappings.

## How click-to-cd works

`open_local.py` only writes to the pane when all of these hold: kitty's shell integration says the cursor is at a prompt, the screen is not the alternate screen (so not in micro, yazi, ...), the pane is not remote, and the tty's foreground process group contains the zsh that last announced its pid via the `kitty_cd_link_pid` user variable (so not a nested shell without the handler).

It then writes `ESC [ 29271 ~`, the path as hex, and BEL. zsh has that trigger bound to a widget that switches to a private keymap, collects hex digits until BEL, decodes, and runs `builtin cd` — the path never passes through the shell parser, so any name is safe. The widget declines at a continuation prompt or in `vared`, leaves `BUFFER` alone, then re-runs the precmd hooks and `reset-prompt` (as fzf's cd widget does) so prompts like powerlevel10k update.

## kitty and macOS quirks this works around

- **Environment of overlays.** `launch --copy-env` copies a process's environment as it was at exec time (macOS `KERN_PROCARGS2`), so variables exported in `.zshrc` are missing. The shell publishes its current `$EDITOR` as the `kitty_editor` user variable and `open_local.py` passes it on explicitly.
- **Plain-click delay.** kitty delays `click` events by `click_interval` to tell them from double clicks. A plain-click `release` mapping guarded by `selection` never fires, because the press has already started a selection; hence `Cmd+click`.
- **Stock path hints.** `kitten hints --type path` opens matches with `open_url_with` (macOS `open`, bypassing `open-actions.conf`), and `--type linenum` types `$EDITOR +LINE file` into the shell. The menu runs those hint types itself and hands the result to kitty as a `file://` link instead.
- **Hyperlinks in custom hints.** `--customize-processing` only sees text with hyperlinks stripped, so `p`/`m` run the stock hyperlink hints with a `custom_callback` and convert the chosen URLs themselves.
- **No translucent overlays.** kitty does not draw a pane under its overlay, so the menu redraws the pane's `screen-ansi` text with every colour blended `DIM_STRENGTH` of the way to the background, using the theme colours it queries from the terminal (OSC 4/10/11, ended by a DA1 request). If the terminal does not answer, it falls back to SGR faint.

## Tests

```zsh
kitty +launch kitty/tests/test_kittens.py   # needs kitty's bundled Python
zsh kitty/tests/kitty-cd-link-tests.zsh
```

The Python suite uses kitty's default options and temporary directories, fakes kitty's window and boss objects, and checks rendering by feeding the menu's output into a real kitty `Screen`. Nothing here drives a live kitty, so a click, the overlays and the menu's look still need checking by hand after changes.
