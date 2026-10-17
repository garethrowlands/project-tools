# kitty shader demo

A self-running show-off of the custom shaders in `kitty/shaders/` (and the
link handling in `kitty/`), made to be screen-recorded. Run `play` in a kitty
pane that is alone in its tab: the pane becomes a presenterm deck, and a
background director opens and closes panes, a tab and a second OS window
around it, types into them and moves the real mouse pointer, so every effect
happens live. Stage panes describe themselves as they go.

Design: `docs/superpowers/specs/2026-10-04-kitty-shader-demo-design.md`.

## Setup (once)

1. kitty ≥ 0.49 with `custom_shaders gentle`, `allow_remote_control
   socket-only` and `listen_on` (already in this repo's kitty setup), and
   `kitty-cd-link.zsh` sourced by your zsh (for the link beat).
2. presenterm, micro, eza, rg and jq on PATH.
3. Hammerspoon, with Accessibility permission, and in `~/.hammerspoon/init.lua`:

   ```lua
   require("hs.ipc")
   demoStage = dofile(os.getenv("HOME") .. "/github.com/garethrowlands/project-tools/kitty/demo/stage.lua")
   ```

   Reload Hammerspoon, then in its console run `hs.ipc.cliInstall("/opt/homebrew")`
   once, so `hs` is on PATH.
4. Check from a kitty pane: `hs -c 'return demoStage.selftest()'` — the
   pointer traces a square in the kitty window with the spotlight following.

## Running

```
kitty/demo/play                    # list the chapters
kitty/demo/play 1                  # chapter 1: shaders (~2 min)
kitty/demo/play 2                  # chapter 2: windows, panes and tabs
kitty/demo/play 3                  # chapter 3: getting around projects (its own kitty instance)
kitty/demo/play 2 --only 4         # one beat
kitty/demo/play 2 --from 4         # from beat 4 on
kitty/demo/play 1 --slow 2         # every pause doubled
kitty/demo/play 1 --dry-run        # print every verb, touch nothing
kitty/demo/play 3 --record ~/Movies/chapter-3.mov   # record the take
```

Chapter 2's beats 2–7 use the panes beat 1 opens, so rehearse them with
`--from 1` rather than `--only`.

Chapter 1's stack beat (9) shows Hammerspoon's list of every window piled on
the TextEdit windows' half of the screen. Any of your own windows there
(browser, editor behind kitty) join the list below the three TextEdit windows,
which the beat never leaves, so it works the same; but their titles show in
the list. For a video you'll share, close or minimise them first.

## Chapter 3 setup (once)

Chapter 3 runs in a kitty instance of its own, against a staged world in
`~/kitty-demo` (override with `DEMO_WORLD`; play refuses a directory it
didn't make), so the window switcher and tidy-windows never see your real
windows. It also needs:

1. A separate Claude Code login for the demo panes:
   `CLAUDE_CONFIG_DIR=~/.claude-demo claude` (log in, `/exit`). It must stay
   under `~/.claude*`: the window switcher looks for titles only there.
2. The two recorded conversations: `kitty/demo/chapters/3-projects/setup-claude`
   (two `claude -p` calls, a few cents; rerun to re-record).
3. `ANTHROPIC_API_KEY` set (tidy-windows makes one real call per take),
   VS Code, and Microsoft Edge as the default browser (⌘B's page opens there).
4. Before each take: quit VS Code, and close any Edge tab on
   github.com/garethrowlands/project-tools (pre-flight checks both: the
   launchers would otherwise reuse, and the demo then close, your own).

## Chapters

Each chapter is `chapters/N-name/` with a `deck.md`, `beats/`, an optional
`scene/` (beats refer to it as `$DEMO_CHAPTER_DIR/scene`) and an optional
`requires`: the kitty actions its keystrokes rely on, one per line. When a
chapter has `requires`, pre-flight checks each action is mapped in
`kitty.conf` or a file it includes, and that kitty is the frontmost app.

A chapter with an `instance` file (chapter 3) runs in a kitty instance of its
own: play runs the chapter's `build-world` (staged repos, zoxide db, a zdotdir
wrapping your own startup files, and a kitty session file), starts kitty on
that session with its own socket, and the session's deck window runs `play
CHAPTER --inside`. Quitting the deck quits that instance; your own kitty is
never touched.

`--record FILE` records the take to a new `.mov`: it starts once the first
slide is up and stops before anything closes, so the video runs from the
first slide to the last with nothing to trim. A take that ran clean quits its own
deck afterwards (so a chain of takes needs no one at the keyboard); a failed or
aborted one leaves the deck up. Hammerspoon runs
`screencapture`, so it needs Screen Recording permission (System Settings ›
Privacy & Security; the first take asks). It records the display kitty is on
(`screencapture -D N`, with N worked out from kitty's window and checked
against the size screencapture captures); set `DEMO_RECORD_DISPLAY=N` (1 is
the main display) if it picks wrongly. Without `--record`, start a screen recording (⇧⌘5) first, then
hands off. Abort with
**Ctrl+Alt+Cmd+.** or by quitting presenterm (`q`); either way the demo closes
everything it opened and restores the window frame and layout. The director's
log is `$TMPDIR/kitty-demo/play.log`; failures also show as a notification.

## Writing a beat

A beat is `chapters/N-name/beats/NN-name.zsh`, sourced in numeric order with ERR_RETURN, so
the first failing verb stops the run. Start each with `slide goto N TEXT` so
`--from`/`--only` work, and use `ensure` for panes an earlier beat would have
left open.

| Verb | Does |
|---|---|
| `slide goto N TEXT` | deck slide N; waits for TEXT |
| `pane open\|ensure NAME [launch options] -- CMD…` | new kitty window, without focus |
| `pane close NAME` | close it (no-op if not open) |
| `card open\|ensure NAME TEXT [launch options]` | a self-describing pane |
| `card say NAME TEXT` | change its text |
| `bell NAME` | that card rings the bell |
| `focus NAME` | keyboard focus there |
| `keys NAME KEY…` / `type-text NAME TEXT` | input to its program (`focused` = whichever has focus) |
| `wait-text NAME TEXT` / `wait-window MATCH` | readiness |
| `mouse glide NAME X% Y% [MS]` / `mouse glide-text NAME TEXT [MS]` / `mouse click [cmd]` | the real pointer |
| `stage open-other FILE` | kitty takes the left half; FILE opens in TextEdit on the right half, focused |
| `stage focus-other TITLE` / `stage focus-main` | move focus between TextEdit's window and kitty |
| `stage close-other TITLE` | close that window (and TextEdit, if the demo started it) |
| `stage open-stack FILE...` | kitty takes the left half; the files open in TextEdit one by one, piled on one another on the right half (the last on top, focused) |
| `stage press-other KEYS` | like `press`, for keys Hammerspoon acts on (the stack keys), with TextEdit frontmost |
| `stage close-stack` | close the pile (and TextEdit, if the demo started it) |
| `stage fill` | main window back to the whole screen |
| `press KEYS` | the real keystroke (e.g. `cmd+shift+enter`), with an on-screen badge |
| `press-focus KEYS` / `press-reorders KEYS` | press, then wait for focus / the pane order to change |
| `press-new NAME KEYS` | press, adopt the one new window as NAME |
| `wait-layout NAME` / `wait-own-tab NAME` | readiness after a layout key / after sending NAME to its own tab |
| `reveal TEXT [SECONDS]` | bring up the deck's next list item (presenterm `incremental_lists`) until TEXT shows, then hold SECONDS (default 3) |
| `beat-pause SECONDS` | pacing (scaled by `--slow`) |
| `adopt NAME MATCH` | name the one window matching MATCH (`var:demo=stray`, `cmdline:"(^\|/)window$"`: quote a regex with brackets) |
| `wait-gone NAME` / `wait-in-tab NAME TITLE` / `wait-tab TITLE` | readiness after a tool closes or moves windows / switches tab |
| `stage tile-next BUNDLE TITLE` / `stage wait-tiled` / `stage close-tiled` | tile a launcher's app window on the right half, then close it (Edge: only its tab) |

## Tests

```
zsh kitty/demo/tests/demo-tests.zsh
kitty +launch kitty/demo/tests/test_demo_geometry.py
```

## Why a geometry kitten?

`kitten @ ls` reports panes' lines and columns but no pixel positions, so
`demo_geometry.py` runs inside kitty and reads `Window.geometry` and
`get_os_window_size()`. They are kitty internals: if a kitty upgrade breaks
them, the first mouse beat of a rehearsal fails with a clear message.
