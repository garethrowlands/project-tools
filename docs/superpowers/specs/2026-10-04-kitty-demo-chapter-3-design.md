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
| Picker data | A staged world of throwaway git repos, zoxide db and project cache under `$TMPDIR/kitty-demo/world/`; the tools run unchanged |
| Isolation | `play 3` runs in a **second kitty instance** (the user's `kitty.conf`, its own `--listen-on` socket, its own environment). The window switcher and tidy-windows list only its windows, so the user's windows can't be closed or moved |
| Environment | The instance is started with `ZDOTDIR` pointing at a staged dir whose `.zshenv`/`.zshrc` source the user's own and then set `PROJECT_ROOTS`, `PROJECT_CACHE`, `_ZO_DATA_DIR` (the user's `.zshenv` exports `PROJECT_ROOTS` unconditionally, and every zsh the overlays start reads it). No dotfile changes |
| Claude Code panes | Real `claude`, under `CLAUDE_CONFIG_DIR=~/.claude-demo` (a persistent profile the user logs into once; `bin/window-list` and `advise` already search `~/.claude*`). Each run seeds two transcripts with fixed `ai-title` lines and resumes them; nothing is prompted, so no API calls |
| tidy-windows | The real API call, against windows staged to have obvious answers; slides stay general; the beat checks the two staged rows' outcome only |
| Launchers | ⌘I and ⌘B, each tiled on the right half while kitty takes the left, held ~2 s, closed, kitty fills again |
| Left out | ⌘N (`note`, the notes picker); Hammerspoon keys; worktrees (`sw`) |

## Staged world

Built fresh by the chapter's `stage` script on each run (pre-flight, before
anything is visible), removed at cleanup (except `~/.claude-demo`'s login).

- **projects/**: `shop-api`, `web-app`, `infra`, `docs`, `blog` — small git
  repos with a few commits each, clean and "pushed": each has an `origin`
  remote and `main` tracks `origin/main`, whose ref is set to HEAD with
  `git update-ref` (no network, nothing is ever pushed), so tidy-windows
  sees nothing unpushed. `web-app`'s `origin` URL is
  `https://github.com/garethrowlands/project-tools.git`, so ⌘B has a real
  public page; the others point at `git@example.com:demo/<name>.git`.
- **zoxide db** (`_ZO_DATA_DIR`) ranking `shop-api` > `web-app` > `infra` >
  `docs` > `blog`, and a **project cache** (`PROJECT_CACHE`) from `PROJECT_ROOTS=world/projects`.
- **~/.claude-demo/projects/…**: two transcripts, each ending in an
  `ai-title` line: "Add rate limiting to orders endpoint" (shop-api) and
  "Move Terraform state to S3" (infra).

Tabs at the start of beat 0 (all tall):

| Tab | Panes | Role |
|---|---|---|
| 1 `web-app` | slides (left), a web-app shell | the deck's home; ⌘I / ⌘B act on web-app |
| 2 `shop-api` | claude (rate limiting), a shell | ⌘§ target |
| 3 `infra` | claude (Terraform) | ⌥⇥ shows its title |
| 4 `docs` | an idle `git log` in docs | tidy-windows: **close** |
| 5 | a lone shop-api shell | tidy-windows: **move** to tab 2 (deterministic, `plan_moves`) |

`blog` has no window: beat 4 opens it.

## Beat script

| # | Slide (shown first) | Keys | What you see | Check |
|---|---|---|---|---|
| 0 | **Getting around projects.** One kitty window, a tab per project. | — | the deck, five tabs | — |
| 1 | **Jump to a project: ⌘§.** Open projects first, then the rest, ranked by how often you go there. | ⌘§ · `shop` · ↩ | the picker over the tab, then tab 2 | focus in tab 2 |
| 2 | **Every window, live: ⌥⇥.** Claude Code panes show their conversation title. | ⌥⇥ · ↓ ↓ (preview follows) · `slides` · ↩ | the list with `[Add rate limiting…]`, `[Move Terraform…]`; back on the deck | focus on deck |
| 3 | **Tidy up: ⌘⇧W.** Claude reviews every window: close the stale, regroup by project. | ⌘⇧W · (wait for the picker) · ↩ | rows pre-selected; tabs 4 and 5 leave the tab bar | `git log` pane gone; stray shell now in tab 2 |
| 4 | **A project with no window opens a new tab.** | ⌘§ · `blog` · ↩, then back (⌃⇧⇥ or ⌥⇥, fixed in rehearsal) | a new `blog` tab, then the deck | new tab cwd is blog; focus on deck |
| 5 | **Open the IDE: ⌘I** | ⌘I | kitty left half, VS Code on web-app right half; it closes, kitty fills | a VS Code window titled web-app |
| 6 | **The project's web page: ⌘B** | ⌘B | Edge on the right half with the GitHub repo; the tab closes | an Edge window titled project-tools |
| 7 | **That's getting around.** The keys, one list item each. | — | — | — |

Tidy-windows' close/keep advice comes from the model: if a take's advice
doesn't close the `git log` pane, beat 3 fails with that message and the
take is rerun (staging aims to make this rare).

## Components

```
kitty/demo/
  play                   + instance mode (below)
  lib.zsh                + verbs below
  stage.lua              + tileNext / closeTiled
  chapters/3-projects/
    deck.md, beats/, requires, layout (tall)
    instance             marks the chapter as needing its own kitty instance
    stage                builds the staged world (zsh), prints its env
    scene/               transcript templates, zdotdir/.zshenv, .zshrc
```

### `play` instance mode

When the chapter has an `instance` file, `play 3` run from the user's kitty
does pre-flight (as before, plus the checks below), runs `stage`, then starts
`kitty --listen-on unix:$DEMO_STATE/kitty.sock --start-as=maximized
--directory world/projects/web-app` with the staged environment, whose first
window runs `play 3 --inside …` (same options). The inner `play` is the one
that presents the deck and directs; `kitten @` reaches the instance through
`KITTY_LISTEN_ON`, as it already does. The outer `play` waits for the
instance to exit and then removes the world. Cleanup (inner) closes the
instance; Hammerspoon pins the instance's window, so the user's kitty is
never moved.

### New verbs

| Verb | Does |
|---|---|
| `tab open NAME DIR [-- CMD…]` | a tab titled NAME with a pane in DIR (used only to stage beat 0's tabs) |
| `press-overlay KEYS` | press, then wait for an overlay window to appear |
| `wait-gone NAME` / `wait-in-tab NAME TAB` | readiness after tidy-windows |
| `wait-focus-tab TITLE` | focus is in the tab titled TITLE |
| `stage tile-next BUNDLE` | arm a watcher: the next window BUNDLE focuses (new, or an existing Edge window gaining a tab) has its frame saved and moves to the right half; kitty takes the left |
| `stage close-tiled` | VS Code: run `close-project` on the project; Edge: ⌘W in that window; restore the window's frame; kitty fills |

### Pre-flight additions

`~/.claude-demo` exists and is logged in; `ANTHROPIC_API_KEY` is set for
the instance; `code` (VS Code) and Microsoft Edge are installed; `zoxide`,
`claude`, `uv` are on PATH; the `requires` actions (`launch --type=overlay
… switch-project` / `window` / `tidy-windows` / `ide` / `project-web`) are
mapped.

## Spike first

Before any beat: does `claude --resume <seeded id>` under
`CLAUDE_CONFIG_DIR=~/.claude-demo` (logged in once) show the seeded
conversation with no API call, and does `bin/window-list` then print the
seeded title (i.e. resume keeps appending to the seeded transcript, or the
title survives into whatever file it writes)? If not, fall back to seeding
`sessions/` state differently or to a one-line live prompt per pane, and
update this spec.

## Testing

- Unit tests (stubbed kitty/Hammerspoon): `stage` builds the repos, remotes,
  zoxide ranking and transcripts; the ZDOTDIR `.zshenv` wins over an
  unconditional `PROJECT_ROOTS`; instance-mode command line; new verbs' dry
  runs; chapter 3 slide gotos match its deck.
- `bin/window-list` against the staged `~/.claude-demo` session files prints
  the seeded titles (needs the spike's answer).
- Rehearsal with `play 3 --from 0`, then full takes.

## Out of scope

⌘N / notes; chapter 4+ (Cmd+P hint menu, links, micro keys); changing the
project tools themselves.
