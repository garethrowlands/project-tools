# kitty demo chapters: chapter support + "Windows, panes and tabs" — design

Extends the self-running kitty demo (`kitty/demo/`, spec
`2026-10-04-kitty-shader-demo-design.md`) into a series of short videos.
This spec covers sub-project 0 (chapter support in `play`) and chapter 2.
Later chapters get their own specs.

## Goal

A series of short (~1–2 min) silent videos for other terminal users, each
recordable on its own. Chapter 2 shows how to work with windows in kitty:
panes, layouts and tabs, all driven by the user's real key mappings, with
the keys made visible.

Success criteria for a chapter 2 take: as chapter 1 (every effect visible,
nothing left behind, pointer stays in kitty, repeatable), plus every key
pressed is shown as a badge long enough to read.

## Chapter series

| # | Chapter | Status |
|---|---|---|
| 1 | Shaders (the existing demo) | done; moves into `chapters/1-shaders/` |
| 2 | Windows, panes and tabs | this spec |
| 3 | Getting around projects: `switch-project`, `window` (with Claude Code sessions), `tidy-windows`, and the `ide` / `project-web` / `note` (Obsidian) launchers | later spec |
| 4+ | Working in a project (Cmd+P hint menu, links in depth, micro keys), notes & web | later, to be regrouped |

Hammerspoon tiling and focus keys stay in chapter 1 (beat 8); chapter 2 is
kitty only.

## Decisions

| Topic | Decision |
|---|---|
| Packaging | One chapter per video; `play <chapter>` runs one |
| Keys | Real keystrokes posted by Hammerspoon, so the user's own `kitty.conf` mappings act |
| Showing keys | On-screen badge (e.g. ⌘→) for each `press`, drawn by Hammerspoon at the bottom centre, ~1.2 s |
| Narration | As chapter 1: one state per slide, each slide shown before its change, with a pause to read |
| Panes | A and B are labelled `card` panes; C is a real shell opened by Cmd+Shift+Enter |
| Starting layout | Each chapter may name one in a `layout` file (default splits, which chapter 1 needs). Chapter 2 starts in **tall**, the user's own layout (they don't use splits); kitty places the panes as it would the user's: slides left, A, B, C stacked right. Focus hops → ↑ ↑ ←; the layout tour goes F, G, S, T and ends back on tall |
| Left out | Cmd+F7 (pick a pane by number; the user doesn't use it), pressing Cmd+Shift+↓ (its "where to?" menu; mentioned on a slide only), Hammerspoon keys |

## Components

```
kitty/demo/
  play, lib.zsh, geometry.zsh, card, stage.lua, demo_geometry.py   shared
  chapters/1-shaders/   deck.md, beats/, scene/   (moved, unchanged)
  chapters/2-windows/   deck.md, beats/
  tests/                demo-tests.zsh, test_demo_geometry.py
```

### `play`

```
play                       list chapters
play CHAPTER [--from N | --only N] [--slow FACTOR] [--dry-run]
```

CHAPTER is a chapter directory's number or full name (`2` or
`2-windows`). `DEMO_CHAPTER_DIR` points at it; beats use it for their
scene files (chapter 1's beats change `$DEMO_ROOT/scene` to
`$DEMO_CHAPTER_DIR/scene`). The director waits for the chapter's first
slide title (the first setext heading in its `deck.md`) instead of the
hard-coded "kitty, with shaders".

### New verbs

| Verb | Does |
|---|---|
| `press KEYS` | Hammerspoon posts the keystroke (e.g. `cmd+right`, `cmd+shift+enter`, `ctrl+alt+z`, `ctrl+shift+tab`) to the frontmost app and shows its badge |
| `press-new NAME KEYS` | records kitty's window ids, presses, waits for exactly one new window, names it NAME and adds it to the cleanup list (fails on none or more than one) |
| `wait-focus NAME` | waits until NAME is kitty's focused window |
| `wait-layout NAME` | waits until the deck's tab reports layout NAME |
| `wait-tabs N` | waits until the main OS window has N tabs |

### `stage.lua`

`press(mods, key, label)` posts the keystroke with `hs.eventtap.keyStroke`
and shows `label` in an `hs.canvas` badge at the bottom centre of the
pinned window's screen, above the tab bar, fading after ~1.2 s (a new
press replaces the badge). The label is built in zsh from KEYS (⌘ ⌥ ⌃ ⇧,
arrows, ↩, ⇥, letters upper-cased). `selftest()` also shows a badge.

## Beat script (chapter 2)

| # | Slide (shown first) | Keys | What you see | ~s |
|---|---|---|---|---|
| 0 | **Windows, panes and tabs in kitty.** Everything here is a real keypress: watch the badge at the bottom. | — | slides alone | 6 |
| 1 | **A new pane, same directory.** Cmd+Shift+Enter splits off a shell that starts where you are. | ⌘⇧↩ | A and B open as labelled cards; the key opens C, which runs `pwd` | 9 |
| 2 | **Move focus with Cmd+arrows.** | ⌘→ ⌘↓ ⌘← ⌘↑ | focus hops slides → A → B → C → slides | 10 |
| 3 | **Move the pane itself: Cmd+Shift+← / →** | ⌘⇧→ ⌘⇧→ | the focused card A moves along | 8 |
| 4 | **Layouts: Cmd+S stack · T tall · F fat · G grid** | ⌘T ⌘F ⌘G ⌘S | the four panes rearranged each way, ~2 s each | 12 |
| 5 | **Zoom one pane: Ctrl+Option+Z, and back** | ⌃⌥Z ⌃⌥Z | the focused pane fills the tab, then returns | 6 |
| 6 | **Send a pane to its own tab: Cmd+Shift+↑** (Cmd+Shift+↓ asks where) | ⌘⇧↑ | B leaves for a new tab | 7 |
| 7 | **Switch tabs: Ctrl+Tab / Ctrl+Shift+Tab** | ⌃⇥ ⌃⇧⇥ | to B's tab and back | 7 |
| 8 | **That's panes, layouts and tabs.** A list of every key used. | — | panes close; slides alone | 6 |

The focus order in beat 2 depends on the splits layout's geometry; the
beat names each target and checks it with `wait-focus`, and rehearsal
fixes the arrow sequence if the arrangement differs. Cmd+S and Cmd+F go
through `micro_keys.py`, which falls back to `goto_layout` when micro is
not in front.

## Failure handling

As chapter 1, plus:

- **Pre-flight**: kitty must be the frontmost app (keystrokes go to it),
  and the mappings chapter 2 needs must be present in `kitty.conf` or a
  file it includes: `neighboring_window`, `move_window_forward`,
  `new_window_with_cwd`, `goto_layout tall` / `fat` / `grid` / `stack`,
  `toggle_layout stack`, `detach_window new-tab`. A missing one is named.
- **Every `press` is checked** by the wait that follows it (`wait-focus`,
  `wait-layout`, `wait-tabs`, or `press-new`'s own wait); a key that does
  nothing fails the beat with a clear message.
- Panes from `press-new` and the detached tab are cleaned up like any
  other window the demo created.

## Testing

- Unit tests (stubbed): chapter selection and listing; every chapter's
  slide gotos match its own deck; `press` sends the right Hammerspoon call
  and badge label; `press-new` registers exactly one new window and fails
  on none or two; dry-run shape of each chapter 2 beat.
- Chapter 1's tests move with it, unchanged in substance.
- `demoStage.selftest()` shows a badge.
- Rehearsal with `play 2 --only N`, then full takes.

## Out of scope

Chapters 3+; Hammerspoon keys in chapter 2; Cmd+F7; pressing Cmd+Shift+↓.
