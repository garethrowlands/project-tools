# kitty demo chapter 4: "Working in a project" — design

Chapter 4 of the kitty demo series (`kitty/demo/`; chapters 1–3 are on
main, see `2026-10-04-kitty-demo-chapter-3-design.md` for the instance and
staged-world machinery this reuses). It shows the in-project helpers in
`kitty/` (see `docs/kitty-links.md`): ⌘-click on hyperlinks, the ⌘P hint
menu, and Mac editing keys in micro, through one small task done start to
finish.

## Goal

A ~2–3 min silent video for other terminal users, in the style chapter 3
settled on: one state per slide, each slide shown before its change, list
items revealed one at a time and held by length, demo slides ending with a
"Watch: <keys>" item, keys written as the badge draws them (⌘P, ⇧⌘Z, ↩),
mechanics not narrated, every key and click a real one with its badge.

Success criteria for a take: every beat's effect is visible in the pane
beside the slides; nothing outside the demo's own kitty instance and
`~/kitty-demo` changes; the take is the same every time (no model calls).

## Decisions

| Topic | Decision |
|---|---|
| Framing | One small task, start to finish: read the to-do, go to the code, fix it, stage it. Each helper appears because the task needs it |
| Staging | Chapter 3's world, in its own kitty instance (same isolation, pre-flight, `--record`). One tab: the slides on the left half, a shell in `~/kitty-demo/shop-api` on the right (tall). No Claude panes, no API calls |
| Shared world | `build-world` moves from `chapters/3-projects/` to `kitty/demo/world/build-world` and no longer writes a session; each instance chapter has a `session` script that writes `session.kitty`. A chapter with a `claude` file needs the recorded Claude sessions (pre-flight and the ai-titles); chapter 4 has none |
| Story files | shop-api gains, committed: `NOTES.md` (the to-do list, "Return 429 with a Retry-After header when a caller is over the limit") and `src/orders.py` (a `# TODO: return 429 …` comment where that happens). Chapter 3 is unaffected (its tidy-up needs shop-api dirty, which it stays) |
| Click badge | The director's ⌘-clicks show a badge too: `⌘ click`, drawn like the key badge, shown 0.7 s before the click |
| Extras | Markdown in glow, and a directory click; not ⌘P m (several paths) or yazi |

## Beat script

| # | Slide (shown first) | Keys / clicks | What you see | Check |
|---|---|---|---|---|
| 0 | **Working in a project** (premise: a small fix without leaving the terminal, in shop-api); **Three helpers** (⌘-click opens links · ⌘P picks things off the screen · micro takes Mac keys) | — | slides beside shop-api's shell | — |
| 1 | **⌘-click a file: Markdown opens rendered**; Watch: ⌘ click NOTES.md | `ls`; ⌘ click `NOTES.md`; `q` | eza lists shop-api with links; glow shows the to-do; back to the shell | glow's overlay appears and closes |
| 2 | **⌘-click a directory: the shell moves there**; Watch: ⌘ click src | ⌘ click `src` | the prompt's directory becomes `src` | `pwd` shows `…/shop-api/src` |
| 3 | **Open it at the line: ⌘P n**; Watch: ⌘P, n, then the hint | `rg TODO` (`--no-heading`, so each hit reads `file:line:`); ⌘P; `n`; the hit's label | the menu over a dimmed pane; micro opens `orders.py` at the TODO line | micro's overlay shows `orders.py` |
| 4 | **Edit with Mac keys** (⌘X cut · ⌘Z / ⇧⌘Z undo, redo · ⌘S save; ⌘C ⌘V ⌘A ⌘F too); Watch: ⌘X, type, ⌘Z, ⇧⌘Z, ⌘S | select the TODO line; ⌘X; type the fix; ⌘Z; ⇧⌘Z; ⌘S; quit micro | the line goes, the fix appears, vanishes, returns; micro reports the save | the file on disk has the fix and no TODO |
| 5 | **Pick a path off the screen: ⌘P f**; Watch: ⌘P, f, then the hint | `git status --short`; type `git add `; ⌘P; `f`; the label; ↩; `git status --short` | the path inserted, shell-quoted; the file staged | `git diff --cached --name-only` is `src/orders.py` |
| 6 | Cheat sheet (one item per key or click) | — | — | — |
| 7 | Closing slide: the files in `kitty/` and where they live | — | — | — |

Settled in rehearsal: the label kitty's hints give the single match (with
one match on screen it is the first label), and the keys micro needs to
select one whole line (e.g. Home, then ⇧↓).

## Components

```
kitty/demo/
  world/build-world        moved from chapters/3-projects/, minus the session
  chapters/3-projects/     session (new: writes chapter 3's session), claude (marker)
  chapters/4-working/      deck.md, beats/, requires, layout (tall), instance, session
  lib.zsh                  mouse click shows the badge
  stage.lua                click(mods, label) shows the badge before clicking
  play                     instance mode runs world/build-world, then the chapter's session;
                           Claude checks only for chapters with a claude file
```

`requires` for chapter 4: `kitten hint_menu.py` (⌘P) and the micro-keys
mappings it presses (`kitten micro_keys.py cmd+x`, `cmd+z`, `cmd+shift+z`,
`cmd+s`). The ⌘-click mapping is a `mouse_map`, which pre-flight's `map`
check doesn't read; beat 1 fails clearly if a click opens nothing.

## Testing

- The refactor: chapter 3's world and session tests pass unchanged against
  `world/build-world` plus chapter 3's `session`; chapter 4's session has one
  tab, the slides and a shop-api shell; pre-flight asks for Claude sessions
  only when the chapter has a `claude` file.
- shop-api's new files are committed, and `rg --no-heading TODO` in it finds
  exactly one hit.
- Chapter 4's deck: slide gotos and reveals match; list slides reveal one at
  a time; demo slides end with "Watch:"; keys appear as their badges; no
  key words; lines ≤ 40 characters; dry-run shapes per beat.
- The click badge: `mouse click cmd` sends the badge label.
- Rehearsal with `play 4 --only N`, then full takes with `--record`.

## Out of scope

⌘P m / several paths; yazi; glow's `e` / `o` keys; anything chapter 3
already shows.
