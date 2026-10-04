# kitty demo chapter 3: "Getting around projects" — design

Chapter 3 of the kitty demo series (`kitty/demo/`, specs
`2026-10-04-kitty-shader-demo-design.md` and
`2026-10-04-kitty-demo-chapters-design.md`). It shows this repo's project
tools driven by their real kitty key bindings: `switch-project` (⌘§), the
window switcher with Claude Code conversation titles (⌥⇥), `tidy-windows`
(⌘⇧W), and the `ide` (⌘I) and `project-web` (⌘B) launchers.

## Goal

A ~1–2 min silent video for other terminal users, in the style of chapters 1
and 2: one state per slide, each slide shown before its change, every key a
real keystroke with its badge, the tall layout, other apps tiled beside
kitty (never overlapping).

Success criteria for a take: as chapter 2, plus the pickers show only the
staged world (nothing of the user's real projects, windows, sessions), the
same every take except tidy-windows' close/keep wording, and nothing the
user had open (kitty windows, VS Code, Edge) is changed by the run.

## Decisions

| Topic | Decision |
|---|---|
| Picker data | A staged world of throwaway git repos in `~/kitty-demo/` (override: `DEMO_WORLD`), plus a zoxide db and project cache under `$TMPDIR/kitty-demo/`; the tools run unchanged. The repos live in `$HOME` because their paths show on camera (`~/kitty-demo/shop-api`) and Claude Code keys transcripts by path, so the path must be stable between runs |
| Isolation | `play 3` runs in a **second kitty instance** (the user's `kitty.conf`, its own `--listen-on` socket, its own environment, its own `--session` file in place of the user's `startup_session`). The window switcher and tidy-windows list only its windows, so the user's windows can't be closed or moved |
| Environment | The instance is started with `ZDOTDIR` pointing at a staged dir whose `.zshenv`/`.zshrc` source the user's own and then set `PROJECT_ROOTS`, `PROJECT_CACHE`, `_ZO_DATA_DIR`, `CLAUDE_CONFIG_DIR` (the user's `.zshenv` exports `PROJECT_ROOTS` unconditionally, and every zsh the overlays start reads it). No dotfile changes |
| Claude Code panes | Real `claude --resume`, under `CLAUDE_CONFIG_DIR=~/.claude-demo` (a persistent profile the user logs into once). It must live in `$HOME` with a `.claude` prefix: `bin/window-list` and `advise` never read `CLAUDE_CONFIG_DIR`, they glob `~/.claude*` dirs that have a `sessions/` subfolder, so a profile under `$TMPDIR` would show no titles. The two conversations are recorded once by `setup-claude` (`claude -p`, a few cents); each run appends a fixed `ai-title` line to each transcript and resumes it; nothing is prompted during a run, so no API calls |
| tidy-windows | The real API call, against windows staged to have obvious answers; slides stay general; the beat checks the two staged rows' outcome only |
| Launchers | ⌘I and ⌘B, each tiled on the right half while kitty takes the left, held ~2 s, closed, kitty fills again |
| Left out | ⌘N (`note`, the notes picker); Hammerspoon keys; worktrees (`sw`) |

## Staged world

`build-world` rebuilds it on each run (outer pre-flight, before anything is
visible). It refuses to touch `~/kitty-demo` unless the directory is absent
or holds its marker file `.kitty-demo-world`. The world is left in place
after a run (the next run rebuilds it at the same paths).

- **Repos** `shop-api`, `web-app`, `infra`, `docs`, `blog` — small git repos
  with a few commits each, clean and "pushed": each has an `origin` remote
  and `main` tracks `origin/main`, whose ref is set to HEAD with
  `git update-ref` (no network, nothing is ever pushed), so tidy-windows
  sees nothing unpushed. `web-app`'s `origin` URL is
  `https://github.com/garethrowlands/project-tools.git`, so ⌘B has a real
  public page; the others point at `git@example.com:demo/<name>.git`.
  `docs`' commits are dated six weeks back, the others today.
- **zoxide db** (`_ZO_DATA_DIR`) ranking `shop-api` > `web-app` > `infra` >
  `docs` > `blog`; the **project cache** (`PROJECT_CACHE`) is deleted, so the
  picker rescans `PROJECT_ROOTS=~/kitty-demo`.
- **Claude transcripts**: `~/.claude-demo/kitty-demo-sessions` (written by
  `setup-claude`) maps `shop-api` and `infra` to session ids; each
  transcript gets a last `ai-title` line: "Add rate limiting to orders
  endpoint" (shop-api), "Move Terraform state to S3" (infra).
- **zdotdir/** and **session.kitty** under `$TMPDIR/kitty-demo/`.

Tabs at the start of beat 0, from the session file (all tall; windows
carry a kitty user var `demo=NAME` so beats can find them):

| Tab | Panes (`demo=`) | Role |
|---|---|---|
| 1 `web-app` | slides (`deck`), a web-app shell (`web-shell`) | the deck's home; ⌘I / ⌘B act on web-app |
| 2 `shop-api` | claude (`shop-claude`), a shell (`shop-shell`) | ⌘§ target |
| 3 `infra` | claude (`infra-claude`) | ⌥⇥ shows its title |
| 4 `docs` | `git log` in its pager (`docs-log`) | tidy-windows: **close** |
| 5 `scratch` | a lone shop-api shell (`stray`) | tidy-windows: **move** to tab 2 (deterministic, `plan_moves`) |

`blog` has no window: beat 4 opens one.

## Beat script

| # | Slide (shown first) | Keys | What you see | Check |
|---|---|---|---|---|
| 0 | **Getting around projects.** One kitty window, a tab per project. | — | the deck, five tabs | — |
| 1 | **Jump to a project: ⌘§.** Open projects first, then the rest, ranked by how often you go there. ⌃⇧⇥ comes back. | ⌘§ · `shop` · ↩ · ⌃⇧⇥ | the picker over the tab, tab 2, the deck again | active tab is `shop-api`, then `web-app` |
| 2 | **Every window, live: ⌥⇥.** Claude Code panes show their conversation title. | ⌥⇥ · ↓ ↓ (preview follows) · ⎋ | the list with `[Add rate limiting…]`, `[Move Terraform…]` | the switcher's overlay opens and closes |
| 3 | **Tidy up: ⌘⇧W.** Claude reviews every window: close the stale, regroup by project. | ⌘⇧W · (wait for the picker) · ↩ | rows pre-selected; tabs 4 and 5 leave the tab bar | `docs-log` gone; `stray` in tab `shop-api` |
| 4 | **A project with no window: ↩ opens a shell there, beside you.** | ⌘§ · `blog` · ↩ | a blog shell beside the slides | one new pane, cwd `~/kitty-demo/blog` |
| 5 | **Open the IDE: ⌘I** | ⌘I | kitty left half, VS Code on web-app right half; it closes, kitty fills | a VS Code window titled web-app |
| 6 | **The project's web page: ⌘B** | ⌘B | Edge on the right half with the GitHub repo; the tab closes | an Edge window titled project-tools |
| 7 | **That's getting around.** The keys, one list item each. | — | — | — |

Query text (`shop`, `blog`) is typed into the picker with `kitten @
send-text`, so it shows in the picker's prompt rather than as badges.
Tidy-windows' close/keep advice comes from the model: if a take's advice
doesn't close `docs-log`, beat 3 fails with that message and the take is
rerun (staging aims to make this rare).

## Components

```
kitty/demo/
  play                   + instance mode (below)
  lib.zsh                + verbs below
  stage.lua              + tileNext / tiledPlaced / closeTiled
  chapters/3-projects/
    deck.md, beats/, requires, layout (tall)
    instance             marks the chapter as needing its own kitty instance
    build-world          builds the staged world, zdotdir and session file
    setup-claude         one-time: records the two conversations
```

### `play` instance mode

When the chapter has an `instance` file, `play 3` run from the user's kitty
does pre-flight (as before, plus the checks below), runs `build-world`,
then runs `kitty --listen-on unix:$DEMO_STATE/kitty.sock
--start-as=maximized -o confirm_os_window_close=0 -o
macos_quit_when_last_window_closed=yes --session $DEMO_STATE/session.kitty`
with the staged environment (and the outer kitty's `KITTY_*` variables
removed). The session's `deck` window runs `play 3 --inside …` (same
options), which presents the deck and directs; `kitten @` reaches the
instance through its own `KITTY_LISTEN_ON`. The inner cleanup closes the
instance's OS window last, so the instance quits and the outer `play`
returns. Hammerspoon pins the instance's window, so the user's kitty is
never moved.

### New verbs

| Verb | Does |
|---|---|
| `adopt NAME MATCH` | wait for exactly one window matching MATCH (e.g. `var:demo=stray`, `cmdline:tidy-windows`); name it NAME (not added to cleanup) |
| `wait-gone NAME` | wait until NAME's window has closed |
| `wait-in-tab NAME TITLE` | wait until NAME's window is in the tab titled TITLE |
| `wait-tab TITLE` | wait until the active tab (of the deck's OS window) is titled TITLE |
| `stage tile-next BUNDLE TITLE` | arm a watcher: when BUNDLE is frontmost with a focused window whose title contains TITLE, save its frame, put it on the right half, kitty on the left |
| `stage close-tiled` | VS Code: close that window; Edge: ⌘W to Edge (closes only the demo tab) and restore the window's frame; quit the app if the demo started it; kitty fills and takes focus |

### Pre-flight additions (outer)

`~/.claude-demo/kitty-demo-sessions` exists and names both sessions;
`ANTHROPIC_API_KEY` is set; VS Code and Microsoft Edge are installed;
`kitty`, `zoxide`, `claude`, `code`, `gh`, `uv`, `git` are on PATH; the
`requires` actions (the five overlay launches) are mapped; `~/kitty-demo`
is absent or marked.

## Spike first

After `setup-claude` (and the user's one-time login to `~/.claude-demo`):
does `claude --resume <id>` in `~/kitty-demo/shop-api` show the recorded
conversation with no new API call, and does `bin/window-list`, run in the
same kitty, print `[Add rate limiting to orders endpoint]` for that window
(i.e. resume keeps the appended `ai-title` as the transcript's last)? If
not, revise this spec before building the beats.

## Testing

- Unit tests (stubbed kitty/Hammerspoon): `build-world` builds the repos,
  remotes, upstreams, zoxide ranking, session file and zdotdir, refuses an
  unmarked `~/kitty-demo`, and appends the ai-title once; the zdotdir
  `.zshenv` wins over an unconditional `PROJECT_ROOTS`; the instance
  command line; the new verbs; chapter 3's slide gotos match its deck and
  each beat's dry-run shape.
- Rehearsal with `play 3`, `play 3 --from N`, then full takes.

## Out of scope

⌘N / notes; chapter 4+ (Cmd+P hint menu, links, micro keys); changing the
project tools themselves.
