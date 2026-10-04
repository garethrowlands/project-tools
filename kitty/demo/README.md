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
kitty/demo/play                 # the whole show (~100 s)
kitty/demo/play --only 6        # one beat
kitty/demo/play --from 6        # from beat 6 on
kitty/demo/play --slow 2        # every pause doubled
kitty/demo/play --dry-run       # print every verb, touch nothing
```

Start a screen recording (Cmd+Shift+5) first, then hands off. Abort with
**Ctrl+Alt+Cmd+.** or by quitting presenterm (`q`); either way the demo closes
everything it opened and restores the window frame and layout. The director's
log is `$TMPDIR/kitty-demo/play.log`; failures also show as a notification.

## Writing a beat

A beat is `beats/NN-name.zsh`, sourced in numeric order with ERR_RETURN, so
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
| `stage tile-beside TITLE` | tile the screen: main window left half, TITLE right half |
| `stage fill` | main window back to the whole screen |
| `beat-pause SECONDS` | pacing (scaled by `--slow`) |

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
