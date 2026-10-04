# kitty shader demo — design

A self-running, screen-recorded show-off of the kitty custom shaders in
`kitty/shaders/` (and the link handling in `kitty/`), driven by a director
script.

## Goal

A ~100 s silent video for other terminal users that makes them realise what
kitty can do. It *shows* rather than tells: every effect happens live on
screen, and the screen explains itself through short captions. It is not a
tutorial; config details stay out of it.

Success criteria for a take:

- every effect is visible at normal playback speed;
- nothing the director created is left behind (panes, tabs, OS windows,
  window frame);
- the mouse pointer never leaves the kitty window(s) being demoed;
- two takes in a row look the same.

## Decisions

| Topic | Decision |
|---|---|
| Audience | Show-off / inspiration, not how-to |
| Narration | On-screen captions only; no voice (music can be added in the edit) |
| Playback | Fully self-running: a director script owns all keyboard and mouse input |
| Deck | presenterm, as an ordinary stage pane — focus-hopped and dimmed like the others; its slides are the running headline |
| Stage | Starts as one OS window holding only the deck pane; panes, a tab and a second OS window are created when a beat needs them and closed as soon as no beat needs them |
| Self-description | Stage panes show text about what is happening to them (`card`), or content that narrates itself (a prose file in micro) |
| Mouse and window frames | Hammerspoon (already installed, already has Accessibility), reached through its `hs` CLI |
| Language | zsh glue (repo convention); geometry maths moves to Python + pytest only if it outgrows a few lines |
| Location | `kitty/demo/`, next to the shaders |

Rejected: running demos from presenterm's `+auto_exec` / `+exec_replace`
blocks (undocumented trigger timing, code visible on slides, and no clean
pause or abort); hand-stepping (inconsistent takes); a synthetic voice
(`say`) for now (needs system-audio capture).

## Components

```
kitty/demo/
  play             director (zsh): pre-flight, runs beats, cleanup
  lib.zsh          verbs the beats are written in
  beats/NN-*.zsh   one file per beat (sourced by play, in order)
  deck.md          presenterm slides, one per beat
  card             self-description program a stage pane runs
  stage.lua        Hammerspoon module: window frames, mouse, abort hotkey
  scene/comet.txt  self-narrating prose file for the cursor beat
  scene/repo/      small sample tree for the link beat (dirs, a TODO hit)
  tests/demo-tests.zsh
  README.md        setup and usage
```

### `play`

```
play [--from N] [--only N] [--dry-run] [--slow FACTOR]
```

Run from the kitty pane that will become the deck, alone in its tab: `play`
records `$KITTY_WINDOW_ID` as `deck`, runs pre-flight in the foreground,
starts the beats as a disowned background process, and `exec`s presenterm on
`deck.md` in the same pane, so the show starts from exactly one pane. The
director's output goes to `$TMPDIR/kitty-demo/play.log`, since the pane is
now presenterm's; failures are also shown as a Hammerspoon notification.
`--dry-run` skips the background/exec step and prints to stdout.

- `--from N` starts at beat N (the deck is moved to slide N first).
- `--only N` runs one beat.
- `--dry-run` prints every verb with its arguments and performs none
  (no kitty, no Hammerspoon).
- `--slow FACTOR` multiplies every `beat-pause`.

### `lib.zsh` verbs

Beats are written only in these verbs, so they read like a script:

| Verb | Does |
|---|---|
| `slide next` / `slide goto N` | send keys to the deck pane |
| `pane open NAME [--location=vsplit\|hsplit\|tab] -- CMD…` | `kitten @ launch`, record NAME → window id, wait until it appears |
| `pane close NAME` | close it and drop it from the cleanup list |
| `os-window open NAME -- CMD…` / `os-window close NAME` | second OS window, positioned beside the main one |
| `focus NAME` | `kitten @ focus-window --match id:…` |
| `keys NAME KEY…` / `type NAME TEXT` | `kitten @ send-key` / `send-text` |
| `card NAME TEXT` | change the text a `card` pane shows |
| `bell NAME` | make that pane's program emit BEL |
| `mouse glide NAME X% Y% [MS]` | eased pointer move to a point inside the pane |
| `mouse click [cmd]` | left click at the pointer, optionally with Cmd |
| `wait-text NAME PATTERN` | poll `kitten @ get-text` until PATTERN appears (readiness) |
| `beat-pause SECONDS` | pacing only (scaled by `--slow`) |

Every verb that calls `kitten @` or `hs` checks the exit status and fails
the beat on error (see Failure handling).

### `card`

A pane program that shows centred, styled text: initial text from its
arguments, and new text whenever its message file
(`$TMPDIR/kitty-demo/card-NAME`) changes. On `SIGUSR1` it prints BEL (used by
`bell` for card panes, so the bell comes from the pane's own program). Plain
zsh with ANSI styling; no new dependencies.

### `stage.lua` (Hammerspoon)

Loaded from `~/.hammerspoon/init.lua` and exposed as `demoStage`:

- `frame()` / `setFrame(x, y, w, h)` for the focused kitty window, and
  frames for a second window by title.
- `glide(x, y, ms)`: moves the pointer from its current position on an
  ease-in-out curve, driven by an `hs.timer` (~60 Hz) so the spotlight
  visibly trails.
- `click(mods)`: `hs.eventtap` left click with optional modifiers.
- Abort hotkey **Ctrl+Alt+Cmd+.**: stops any glide and sends SIGTERM to
  `play` (pid file in `$TMPDIR/kitty-demo/`).
- `selftest()`: moves the pointer in a small square and returns the kitty
  window's frame and the final pointer position.

### Mouse geometry

`mouse glide NAME X% Y%` resolves to screen points from:

1. the OS window's frame in screen points, from `demoStage.frame()`;
2. the pane's cell geometry from `kitten @ ls` (`columns`, `lines`, and the
   window's position within the OS window) together with the cell size.

The conversion is a pure function (frame + ls JSON + percentages → point),
tested against fixture JSON. Before beat 0 the main window is set to a fixed
frame (centred, 1600×1000 points) so takes are consistent; its original frame
is restored at cleanup.

## Beat script

Panes: **deck** (presenterm), **A**, **B**, **C** (`card` unless noted).

| # | Deck caption | Stage action | Panes after |
|---|---|---|---|
| 0 | **kitty, with shaders** / *everything you're about to see is live* | Deck alone, full window. ~8 s | deck |
| 1 | *Focus follows you* | Open A (vsplit, "New pane. I just got focus — see my edges glow."), then B (hsplit under A). Focus deck → A → B → deck; each card switches between "focused ✦" and "dimmed — not focused". ~12 s | deck, A, B |
| 2 | *…and when you switch tabs* | Open C in a new tab ("A whole new tab — it glowed on arrival."); Ctrl+Tab back. Close A and B. ~8 s | deck, C (tab 2) |
| 3 | *Where did the cursor go?* | Open A running `micro scene/comet.txt`; send End, Ctrl+End, Ctrl+Home, then a find for `search hit`. The comet trails each jump. Close A. ~14 s | deck, C |
| 4 | *Your mouse gets a spotlight* | Pointer glides slowly across the deck and back. ~10 s | deck, C |
| 5 | *Clicks ripple* | The slide carries a paragraph and the ripple's pipeline group; three clicks on words in it, a pause after each. The ripple only bends existing text (on empty background it is invisible), so clicks always aim at text. ~8 s | deck, C |
| 6 | *Which pane rang?* | Open A ("I'll ring in 3… 2… 1…"); it rings while focus stays on the deck. Close A. ~10 s | deck, C |
| 7 | *…even in another tab* | C counts down and rings in tab 2: the tab area flashes and 🔔 shows on its tab title. Close C (and tab 2). ~8 s | deck |
| 8 | *Which window am I typing in?* | Open a second OS window beside the main one ("I'm a separate kitty window. When I have focus, I get the amber edge."). Alternate focus between windows twice. Close it. ~14 s | deck |
| 9 | *Click a link, land in a terminal app* | Open A: a shell in `scene/repo` that runs `eza --hyperlink` and `rg --hyperlink-format=kitty TODO`. Glide to an `rg` hit, Cmd+click → micro opens at that line; Esc. Glide to a directory in the `eza` listing, Cmd+click → the shell cds. Close A. ~14 s | deck |
| 10 | **gentle.pipeline** / *kitty ≥ 0.49 · custom_shaders* | One last glide and click on the title text, then stillness for a fade. ~8 s | deck |

`scene/comet.txt` narrates its own jumps: line 1 ends "…in a moment it jumps
to the end of this line →", the last line says "…and now down here. Watch the
comet.", and a mid-file line contains `search hit`.

## Failure handling

- **Cleanup always runs.** `play` keeps a list of everything it created
  (window ids, the tab, the second OS window, the original frame) and a
  `trap` on EXIT/INT/TERM closes them and restores the frame. Only recorded
  ids are matched; no other kitty window is touched.
- **Abort from anywhere** with the Hammerspoon hotkey; the trap then tidies
  up. Quitting presenterm (q / Ctrl+C in the deck) also aborts: every verb
  first checks the deck window still exists.
- **End state.** After a full run, or any abort, the screen is back to the
  deck pane alone; presenterm stays open on its current slide.
- **Pre-flight, before anything visible happens.** `play` runs these in the
  foreground, before the `exec`, and exits with a reason on stdout and no
  changes if any fails:
  - `kitten @ ls` reaches this kitty;
  - `hs -c 'demoStage.selftest ~= nil'` answers and a pointer-position probe
    works (Accessibility granted);
  - `presenterm`, `micro`, `eza`, `rg` are on PATH;
  - warning only: `custom_shaders gentle` is not in
    `~/.config/kitty/kitty.conf`.
- **Fail loudly mid-beat.** A failing verb logs `beat N · VERB ARGS:
  ERROR`, shows it as a notification, stops the run and triggers cleanup.
  No retries.
- **Readiness by polling, not sleeping.** Pane creation waits on `kitten @
  ls`; program start-up and slide changes wait on `wait-text`. `beat-pause`
  is only for pacing. Every poll times out (5 s) into a beat failure.

## Testing

- **Unit tests** — `kitty/demo/tests/demo-tests.zsh`, in the style of the
  existing `*-tests.zsh` suites (exit 1 on any failure), added to the test
  list in `CLAUDE.md`:
  - geometry: fixture `kitten @ ls` JSON + frame + percentages → expected
    screen point;
  - name → id bookkeeping and the cleanup list;
  - `--from` / `--only` beat selection;
  - `--dry-run` output for a beat matches the expected verb sequence.
- **`stage.lua`** — kept small; checked with `demoStage.selftest()`.
- **Rehearsal** — `--only`, `--from`, `--dry-run`, `--slow`.
- **Acceptance** — a full take recorded with Cmd+Shift+5, watched back
  against the success criteria above, twice.

## One-time setup

Documented in `kitty/demo/README.md` and added to the install-scripts skill:

1. In `~/.hammerspoon/init.lua`: `require("hs.ipc")` and load
   `kitty/demo/stage.lua`; reload Hammerspoon; run `hs.ipc.cliInstall()`
   once so `hs` is on PATH.
2. Confirm Hammerspoon has Accessibility permission.
3. kitty already has `allow_remote_control socket-only` and `listen_on`;
   nothing new.

## Out of scope

Synthetic voice; automated video capture or editing; demos of the Cmd+P hint
menu, micro keys and project pickers; light-theme takes.
