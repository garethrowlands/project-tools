# kitty demo chapter 4 "Working in a project" Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `kitty/demo/play 4` shows one small task in shop-api (read the to-do in glow, ⌘-click into `src`, ⌘P n to open the TODO in micro, fix and ⌘S, ⌘P f to stage it), in its own kitty instance.

**Architecture:** The staged world builder becomes shared (`kitty/demo/world/build-world`, no session); each instance chapter writes its own session (`chapters/N/session`). Pre-flight's Claude and launcher checks become per-chapter (a `claude` marker file; the launchers named in `requires`). The director gains a badge for ⌘-clicks, a `wait-file` verb and glyphs for Home/End. Chapter 4 is a deck, a session and seven beats.

**Tech Stack:** zsh, kitty 0.49 (sessions, remote control, hints kittens), Hammerspoon (Lua), presenterm, micro, glow, eza, rg, git.

**Spec:** `docs/superpowers/specs/2026-10-10-kitty-demo-chapter-4-design.md`

## Global Constraints

- Chapter 3 must behave exactly as before: its existing tests pass with only the helper that invokes the world builder changed.
- The world stays in `${DEMO_WORLD:-$HOME/kitty-demo}`, touched only if absent or marked `.kitty-demo-world`.
- Slide style (chapter 3's): one state per slide, slide before its change; list items via `<!-- incremental_lists: true -->` and `reveal TEXT SECONDS`; demo slides end with `* Watch: …`; keys written as their badges (⌘P, ⌘S, ⌃Q, ↩); no key words (Cmd+, Ctrl+, Option+, Shift+, Enter, Esc); lines ≤ 40 characters; mechanics not narrated.
- No model calls in chapter 4; no Claude panes.
- Tests: `zsh kitty/demo/tests/demo-tests.zsh </dev/null` (stdin must not be a pipe). Sections that need the kitty/Hammerspoon stubs go above `# --- play ---`; others above `# (later tasks add sections above this line)`.
- The sandbox can't reach kitty, Hammerspoon or `~/kitty-demo`; rehearsal is the user's (Task 6).

## Review Focus

1. A `requires` line containing `+` (e.g. `kitten micro_keys.py cmd+s`): pre-flight's grep treats it as a regex and reports it missing though it is mapped. Expect it found (test in Task 3).
2. Chapter 4 run with no recorded Claude sessions, no API key, VS Code running and an Edge project-tools tab open: none of those concern chapter 4, so expect pre-flight to pass (tests in Task 2).
3. shop-api's tree for chapter 4: chapter 3 needs it dirty; chapter 4's `git status` must list only `orders.py`, so the hint label is unambiguous. Expect chapter 4's session to restore `NOTES.md` (test in Task 4).
4. micro's autoclose: typing the fix with brackets could double them. Expect the fix text to contain only `(` `)` and to be checked on disk after ⌘S (`wait-file`), so a mangled edit fails the beat (Task 4; rehearsal confirms).
5. A ⌘-click badge must appear before the click, like keys, and clicks without modifiers (chapter 1's ripples) must stay unbadged (tests in Task 3).

---

### Task 1: Shared world builder; chapter 3 session script

**Files:**
- Create: `kitty/demo/world/build-world` (moved from `kitty/demo/chapters/3-projects/build-world`, session part removed)
- Create: `kitty/demo/chapters/3-projects/session`, `kitty/demo/chapters/3-projects/claude`
- Delete: `kitty/demo/chapters/3-projects/build-world`
- Modify: `kitty/demo/chapters/3-projects/setup-claude` (path to build-world), `kitty/demo/play` (`demo_run_instance`)
- Test: `kitty/demo/tests/demo-tests.zsh` (`# --- chapter 3 world ---`, `# --- instance mode ---`)

**Interfaces:**
- Produces: `world/build-world [--no-claude] WORLD STATE` (exit 0/1/2 as before; writes repos, marker, `STATE/zoxide`, `STATE/zdotdir`, removes `STATE/projects.txt`, appends ai-titles unless `--no-claude`).
- Produces: `chapters/N/session WORLD STATE -- DECK-CMD...` writes `STATE/session.kitty` (exit 2 on usage).
- Produces: `DEMO_BUILD_WORLD` (default `$DEMO_ROOT/world/build-world`), used by `demo_run_instance`, so tests can fake it.
- `demo_run_instance` runs `zsh $DEMO_BUILD_WORLD [--no-claude] WORLD STATE` (`--no-claude` unless the chapter has a `claude` file), then `zsh $DEMO_CHAPTER_DIR/session WORLD STATE -- $DEMO_ROOT/play <chapter> --inside OPTIONS…`.

- [ ] **Step 1: Adapt the tests (red).** In `# --- chapter 3 world ---`, replace the helper and the direct `build-world` calls:

```zsh
# the world, then chapter 3's session on it (as play does)
bw() {
  local -a nc; [[ $1 == --no-claude ]] && { nc=(--no-claude); shift }
  CLAUDE_DEMO_DIR=$CD zsh $DEMO_ROOT/world/build-world $nc $1 $2 || return
  CLAUDE_DEMO_DIR=$CD zsh $C3/session "$@"
}
```

and change these lines (the rest of the section stays):

```zsh
CLAUDE_DEMO_DIR=$T/nothing zsh $DEMO_ROOT/world/build-world $T/w4 $T/s4 >/dev/null 2>$T/bw.err
CLAUDE_DEMO_DIR=$T/nothing zsh $DEMO_ROOT/world/build-world --no-claude $T/w5 $T/s5 >/dev/null 2>&1
zsh $DEMO_ROOT/world/build-world $T/w6 >/dev/null 2>&1; is 'build-world without a state dir is a usage error' $? 2
zsh $C3/session $T/w6 $T/s6 >/dev/null 2>&1; is 'a session without a deck command is a usage error' $? 2
[[ -e $C3/claude ]] && ok 'chapter 3 uses Claude' || bad 'chapter 3 has no claude marker'
[[ ! -e $C3/build-world ]] && ok 'chapter 3 has no world builder of its own' || bad 'chapter 3 still has build-world'
```

In `# --- instance mode ---`, the fake outer run now fakes the world builder through `DEMO_BUILD_WORLD` and gives `ch9` a fake `session`:

```zsh
mkdir -p $T/ch9/beats $T/bin9
print -r -- '' >| $T/ch9/instance
print -r -- 'print -r -- "$*" >| '$T'/bw9.args' >| $T/bw9
print -r -- 'print -r -- "$*" >| '$T'/session9.args' >| $T/ch9/session
...
( DEMO_BUILD_WORLD=$T/bw9 DEMO_CHAPTER_DIR=$T/ch9 DEMO_WORLD=$T/w9 KITTY_LISTEN_ON=unix:/outer PATH=$T/bin9:$PATH demo_run_instance --from 2 )
is 'outer run builds the world, without Claude for a chapter that has no claude file' "$(<$T/bw9.args)" "--no-claude $T/w9 $T/st9"
is 'outer run writes the chapter session with an inner play' "$(<$T/session9.args)" "$T/w9 $T/st9 -- $DEMO_ROOT/play ch9 --inside --from 2"
```

Run: `zsh kitty/demo/tests/demo-tests.zsh </dev/null | grep ^FAIL` — Expected: FAILs from `build-world succeeds` on (no `world/build-world`), and the two outer-run lines.

- [ ] **Step 2: Move and split.**
  - `git mv kitty/demo/chapters/3-projects/build-world kitty/demo/world/build-world`.
  - In `world/build-world`: header becomes `# build-world: (re)build the staged world chapters 3 and 4 run in (see the chapter 3 spec). … build-world [--no-claude] WORLD STATE`; usage `(( $# == 2 )) || usage` after the `--no-claude` shift, with `world=${1:a} state=${2:a}`; error messages that name `setup-claude` point at `${0:A:h}/../chapters/3-projects/setup-claude`; delete the `# the session: …` block entirely (the Claude-trust and ai-title block stays).
  - Create `chapters/3-projects/session` (`chmod +x`) holding the removed block:

```zsh
#!/usr/bin/env zsh
# session: write chapter 3's kitty session (see the chapter 3 spec).
#
#   session WORLD STATE -- DECK-CMD...
#
# Five tabs, every window tagged with a demo= user var; the deck window runs
# DECK-CMD. The two Claude panes resume the sessions named in
# $CLAUDE_DEMO_DIR/kitty-demo-sessions (setup-claude writes it).

setopt err_exit
(( $# >= 4 )) && [[ $3 == -- ]] || { print -ru2 -- 'usage: session WORLD STATE -- DECK-CMD...'; exit 2 }
world=${1:a} state=${2:a}; shift 3
typeset -A SID
sessions=${CLAUDE_DEMO_DIR:-$HOME/.claude-demo}/kitty-demo-sessions
if [[ -r $sessions ]]; then
  while read -r name id; do [[ -n $name && $name != '#'* ]] && SID[$name]=$id; done < $sessions
fi
{
  <the block's print lines, unchanged>
} >| $state/session.kitty
```

  - `chapters/3-projects/claude`: `# This chapter shows Claude Code sessions and makes a Claude API call (tidy-windows): pre-flight checks for both, and the world gets the sessions' titles.`
  - `setup-claude`: `zsh $here/../../world/build-world --no-claude $world $state` (no `-- true`).
  - `play`: next to `demo_instance_cmd`, `typeset -g DEMO_BUILD_WORLD=${DEMO_BUILD_WORLD:-$DEMO_ROOT/world/build-world}`; `demo_run_instance` becomes:

```zsh
# demo_run_instance OPTION...: build the world, write the chapter's session
# (whose deck runs play --inside with the same OPTIONs), start its kitty and
# wait for it to quit.
demo_run_instance() {
  local world=${DEMO_WORLD:-$HOME/kitty-demo}
  local -a nc
  [[ -e $DEMO_CHAPTER_DIR/claude ]] || nc=(--no-claude)
  mkdir -p $DEMO_STATE
  zsh $DEMO_BUILD_WORLD $nc $world $DEMO_STATE || return 1
  zsh $DEMO_CHAPTER_DIR/session $world $DEMO_STATE -- $DEMO_ROOT/play ${DEMO_CHAPTER_DIR:t} --inside "$@" || return 1
  demo_instance_cmd $world
  "${reply[@]}"
}
```

- [ ] **Step 3: Run the tests** — Expected: no FAIL lines; chapter 3's session assertions pass unchanged.

- [ ] **Step 4: Commit** — `git add -A kitty/demo && git commit -m "kitty demo: share the world builder; chapter 3 writes its own session"`.

---

### Task 2: Per-chapter pre-flight; chapter 4's story files in shop-api

**Files:**
- Modify: `kitty/demo/play` (`demo_preflight_instance`), `kitty/demo/world/build-world` (shop-api's files)
- Test: `kitty/demo/tests/demo-tests.zsh`

**Interfaces:**
- `demo_preflight_instance` checks Claude sessions and `ANTHROPIC_API_KEY` only when `$DEMO_CHAPTER_DIR/claude` exists; VS Code (installed, not running) only when `requires` has a line ending `current ide`; Edge (installed, no project-tools tab) only when it has one ending `current project-web`; `claude` on PATH only with the marker, `code` only with `ide`, `gh` only with `project-web`.
- shop-api, committed: `NOTES.md` (Markdown to-do list) and `src/orders.py` (one `TODO`).

- [ ] **Step 1: Tests (red).** In `# --- review fixes ---`, after the VS Code / Edge pre-flight tests:

```zsh
# chapter 4 neither uses Claude nor the launchers: none of their checks apply
mkdir -p $T/ch10; : >| $T/ch10/instance; print -r -- 'kitten hint_menu.py' >| $T/ch10/requires
out=$(ANTHROPIC_API_KEY= CLAUDE_DEMO_DIR=$T/none DEMO_WORLD=$T/w10 DEMO_CHAPTER_DIR=$T/ch10 demo_preflight_instance 2>&1)
[[ $out != *setup-claude* && $out != *ANTHROPIC_API_KEY* ]] && ok 'pre-flight skips Claude for a chapter without a claude file' || bad "ch10 pre-flight: $out"
[[ $out != *'VS Code'* && $out != *Edge* && $out != *edgemac* && $out != *VSCode* ]] && ok 'pre-flight skips the launchers a chapter does not press' || bad "ch10 pre-flight: $out"
```

In `# --- chapter 3 world ---`:

```zsh
is 'shop-api has its to-do in NOTES.md' "$(git -C $W/shop-api show HEAD:NOTES.md | grep -c 'Return 429 with a Retry-After header')" 1
is 'shop-api has exactly one TODO, in src/orders.py' "$(cd $W/shop-api && command rg --no-heading -n TODO | cut -d: -f1,2)" 'src/orders.py:9'
git -C $W/shop-api ls-files --error-unmatch src/orders.py >/dev/null 2>&1 && ok 'orders.py is committed' || bad 'orders.py is not committed'
```

Expected red: the three pre-flight/story lines fail.

- [ ] **Step 2: Implement.** In `demo_preflight_instance`, wrap the existing checks:

```zsh
  local uses_claude=0 uses_ide=0 uses_web=0
  [[ -e $DEMO_CHAPTER_DIR/claude ]] && uses_claude=1
  grep -q 'current ide$' $DEMO_CHAPTER_DIR/requires 2>/dev/null && uses_ide=1
  grep -q 'current project-web$' $DEMO_CHAPTER_DIR/requires 2>/dev/null && uses_web=1
  local -a cmds=(kitty zoxide uv git)
  (( uses_claude )) && cmds+=(claude)
  (( uses_ide )) && cmds+=(code)
  (( uses_web )) && cmds+=(gh)
```

then guard the API-key and sessions checks with `if (( uses_claude ))`, the VS Code checks (installed, not running) with `(( uses_ide ))`, the Edge checks with `(( uses_web ))`. The world-marker check stays unconditional.

In `world/build-world`, after the `make_repo` loop and before the dev server, write and commit shop-api's story files:

```zsh
# shop-api's to-do and the code it is about (chapter 4 reads one, fixes the
# other); committed, so chapter 4's git status shows only its own change
cat >| $world/shop-api/NOTES.md <<'NOTES'
# shop-api notes

## To do

- [ ] Return 429 with a Retry-After header when a caller is over the limit
NOTES
mkdir -p $world/shop-api/src
cat >| $world/shop-api/src/orders.py <<'ORDERS'
"""The orders endpoint."""

LIMIT = 100  # requests per minute, per caller


def create_order(caller, order, limiter, store):
    """POST /orders"""
    if limiter.over(caller, LIMIT):
        return None  # TODO: return 429 with a Retry-After header
    return 201, store.save(order)
ORDERS
git -C $world/shop-api add NOTES.md src/orders.py
git -C $world/shop-api -c user.name=Demo -c user.email=demo@example.com commit -q -m 'Orders endpoint and to-do'
git -C $world/shop-api update-ref refs/remotes/origin/main HEAD
```

(The dev-server commit and the dirty `NOTES.md` append that follow stay as they are.)

- [ ] **Step 3: Run the tests** — Expected: no FAIL lines.
- [ ] **Step 4: Commit** — `git commit -am "kitty demo: pre-flight checks only what a chapter uses; shop-api gets its to-do and TODO"`.

---

### Task 3: Director: click badge, `wait-file`, Home/End glyphs, literal `requires`

**Files:**
- Modify: `kitty/demo/lib.zsh` (`mouse click`, new `wait-file`, `demo_press_args`), `kitty/demo/stage.lua` (`M.click`), `kitty/demo/play` (`demo_missing_mappings`), `kitty/demo/README.md` (verb table)
- Test: `kitty/demo/tests/demo-tests.zsh` (stubbed section `# --- click badge, wait-file ---`; `# --- play ---` for requires)

**Interfaces:**
- `mouse click cmd` calls `demoStage.click({"cmd"}, "⌘ click")` and waits for the badge's lead; `mouse click` calls `demoStage.click({})` with no badge.
- `demoStage.click(mods, label)`: with a label, shows it as a badge and clicks after `BADGE_LEAD`; without, clicks at once (as now).
- `wait-file PATH TEXT`: waits until the file contains TEXT.
- `demo_press_args`: `home` → `↖`, `end` → `↘`.
- `demo_missing_mappings` matches `requires` lines literally.

- [ ] **Step 1: Tests (red).**

```zsh
# --- click badge, wait-file ---
reset_stubs
mouse click cmd >/dev/null 2>&1
grep -qF 'demoStage.click({"cmd"}, "⌘ click")' $T/hcalls && ok 'a cmd-click shows its badge' || bad "cmd click: $(grep click $T/hcalls)"
reset_stubs; mouse click >/dev/null 2>&1
grep -qx 'return demoStage.click({})' $T/hcalls && ok 'a plain click has no badge' || bad "plain click: $(grep click $T/hcalls)"
grep -q 'function M.click(mods, label)' $DEMO_ROOT/stage.lua && ok 'stage.lua click takes a badge label' || bad 'stage.lua click has no label'
print -r -- 'return None  # TODO' >| $T/f.py
wait-file $T/f.py 'too_many_requests' 2>/dev/null && bad 'wait-file passed before the text was there' || ok 'wait-file waits for the text'
print -r -- 'return too_many_requests(retry_after=60)' >| $T/f.py
wait-file $T/f.py 'too_many_requests' && ok 'wait-file sees the text' || bad 'wait-file missed the text'
is 'home and end badges' "$(demo_badge home) $(demo_badge shift+end)" '↖ ⇧↘'
```

Above `# (later tasks …)`:

```zsh
print -r -- 'map cmd+s       kitten micro_keys.py cmd+s       save' >| $T/plus.conf
print -r -- 'kitten micro_keys.py cmd+s' >| $T/plus.req
is 'a requires line with + is matched literally' "$(demo_missing_mappings $T/plus.req $T/plus.conf)" ''
print -r -- 'kitten micro_keys.py cmds' >| $T/plus2.req
is '...and only literally' "$(demo_missing_mappings $T/plus2.req $T/plus.conf)" 'kitten micro_keys.py cmds'
```

Expected red: all but the wait-file negative.

- [ ] **Step 2: Implement.**
  - `lib.zsh`, `mouse` `click)` branch:

```zsh
    click)
      # a modified click (⌘ click) shows its badge first, as keys do
      local mods='{}' args
      [[ -n $1 ]] && mods="{\"$1\"}"
      args=$mods
      [[ $1 == cmd ]] && args="$mods, \"⌘ click\""
      [[ $(demo_hs "return demoStage.click($args)") == ok ]] || { demo_err "mouse click failed"; return 1 }
      [[ $1 == cmd ]] && demo_sleep 0.7
      demo_sleep 0.1 ;;
```

  - `lib.zsh`, after `wait-window`:

```zsh
# wait-file PATH TEXT: wait until the file PATH contains TEXT (an edit saved).
wait-file() {
  demo_dry wait-file "$@" && return 0
  demo_poll "'$2' in $1" grep -qF -- "$2" $1
}
```

  - `demo_press_args`: `local -A keyglyph=(left ← right → up ↑ down ↓ enter ↩ return ↩ tab ⇥ escape ⎋ home ↖ end ↘)`.
  - `stage.lua`:

```lua
-- Left click at the pointer, with modifiers such as {"cmd"}. With a label
-- (e.g. "⌘ click"), its badge shows first and the click follows BADGE_LEAD
-- later, as a key's does.
function M.click(mods, label)
  local function doClick()
    local p = hs.mouse.absolutePosition()
    events.newMouseEvent(events.types.leftMouseDown, p, mods or {}):post()
    hs.timer.usleep(40000)
    events.newMouseEvent(events.types.leftMouseUp, p, mods or {}):post()
  end
  if label then
    showBadge(label, BADGE_LEAD + BADGE_HOLD)
    hs.timer.doAfter(BADGE_LEAD, doClick)
  else
    doClick()
  end
  return "ok"
end
```

  - `play`, `demo_missing_mappings`: escape regex characters before matching:

```zsh
    grep -qE -- " ${req//(#m)[][\\.^$*+?(){}|]/\\$MATCH}( |\$)" <<<$maps || print -r -- $req
```

(add `setopt local_options extended_glob` at the top of the function if `(#m)` isn't already enabled; `play` sets `extended_glob` globally.)
  - README verb table: add `| \`wait-file PATH TEXT\` | readiness after an edit is saved |`, and note under `mouse click [cmd]` that a ⌘ click shows a `⌘ click` badge.

- [ ] **Step 3: Run the tests** — Expected: no FAIL lines (chapter 1's click beats still dry-run).
- [ ] **Step 4: Commit** — `git commit -am "kitty demo: badge ⌘-clicks; wait-file; match requires literally"`.

---

### Task 4: Chapter 4

**Files:**
- Create: `kitty/demo/chapters/4-working/{instance,layout,requires,session,deck.md}`, `beats/{00-intro,01-notes,02-dir,03-open,04-stage,05-cheat,06-closing}.zsh`
- Test: `kitty/demo/tests/demo-tests.zsh` (new section `# --- chapter 4 ---`)

**Interfaces:**
- Consumes: `world/build-world`, the session contract (Task 1); `adopt`, `wait-gone`, `wait-text`, `wait-file`, `reveal`, `press`, `press-new` not used; `mouse glide-text`, `mouse click cmd` (Task 3).
- The session's one tab is `work`: the deck (`demo=deck`, cwd the world) and a shell in shop-api (`demo=work`).

- [ ] **Step 1: Tests (red).**

```zsh
# --- chapter 4 ---------------------------------------------------------------------
C4=$DEMO_ROOT/chapters/4-working
W4=$T/world4 S4=$T/state4
zsh $DEMO_ROOT/world/build-world --no-claude $W4 $S4 >/dev/null 2>&1 && zsh $C4/session $W4 $S4 -- echo deck >/dev/null 2>&1
is 'ch4 session: one tab' "$(grep -c '^new_tab' $S4/session.kitty)" 1
is 'ch4 session: the deck and a shop-api shell' "$(grep '^launch' $S4/session.kitty | sed 's/ .echo.*//' | paste -sd, -)" 'launch --hold --var demo=deck,launch --var demo=work'
is 'ch4 work shell starts in shop-api' "$(grep -B1 'demo=work' $S4/session.kitty | head -1)" "cd $W4/shop-api"
is 'ch4 restores NOTES.md, so git status lists only its own change' "$(git -C $W4/shop-api status --porcelain)" ''
[[ -e $C4/instance && ! -e $C4/claude ]] && ok 'ch4 has its own kitty and no Claude' || bad 'ch4 instance/claude markers'
is 'ch4 starts in tall' "$(<$C4/layout)" tall
for req in 'kitten hint_menu.py' 'kitten micro_keys.py cmd+s'; do
  grep -qx -- $req $C4/requires && ok "ch4 requires $req" || bad "ch4 requires lacks $req"
done
slides4=("${(@ps:<!-- end_slide -->:)$(<$C4/deck.md)}")
is 'ch4 has 9 slides' $#slides4 9
is 'ch4 slides fit beside a pane' "$(perl -CSD -nle 'print if length > 40' $C4/deck.md)" ''
is 'ch4 names keys by symbol' "$(grep -nE 'Cmd\+|Ctrl\+|Option\+|Shift\+|\bEnter\b|\bEsc\b' $C4/deck.md)" ''
for f in $C4/beats/*.zsh; do
  cur=0
  for line in ${(f)"$(grep -E '^(slide goto|reveal) ' $f)"}; do
    words=(${(Q)${(z)line}})
    if [[ $words[1] == slide ]]; then
      cur=$words[3]
      [[ $slides4[$cur] == *"$words[4]"* ]] && ok "ch4 ${f:t:r}: slide $cur says '$words[4]'" || bad "ch4 ${f:t:r}: slide $cur doesn't say '$words[4]'"
      continue
    fi
    [[ $slides4[$cur] == *"$words[2]"* ]] && ok "ch4 ${f:t:r}: reveal '$words[2]' on slide $cur" || bad "ch4 ${f:t:r}: reveal '$words[2]' not on slide $cur"
  done
done
for n in {2..8}; do
  [[ $slides4[$n] == *'<!-- incremental_lists: true -->'* ]] && ok "ch4 slide $n reveals its list" || bad "ch4 slide $n shows its list at once"
done
for n in 3 4 5 6 7; do
  last=$(print -r -- $slides4[$n] | grep '^\* ' | tail -1)
  [[ $last == '* Watch: '* ]] && ok "ch4 slide $n ends with Watch:" || bad "ch4 slide $n ends with: $last"
done
items4=$(print -r -- ${(F)slides4[2,8]} | grep -c '^\* ')
is 'ch4 reveals every list item' "$(cat $C4/beats/*.zsh | grep -c '^reveal ')" $items4
DEMO_WORLD=$W4 zsh $DEMO_ROOT/play 4 --dry-run >/dev/null 2>&1 && ok 'chapter 4 dry-runs' || bad 'chapter 4 fails its dry run'
shape4() { DEMO_WORLD=$W4 zsh $DEMO_ROOT/play 4 --dry-run --only $1 2>&1 | grep -E '^(press|adopt|wait-|type-text|mouse)' | awk '{print $1, $2}' | paste -sd, - }
is 'ch4 beat 1 opens NOTES.md in glow' "$(shape4 1)" 'adopt work,type-text work,wait-text work,mouse glide-text,mouse click,adopt glow,wait-text glow,press q,wait-gone glow'
is 'ch4 beat 2 clicks into src' "$(shape4 2)" 'adopt work,mouse glide-text,mouse click,type-text work,wait-text work'
is 'ch4 beat 3 opens the TODO at its line, fixes it and saves' "$(shape4 3)" \
  'adopt work,type-text work,wait-text work,press cmd+p,press n,press 1,adopt micro,wait-text micro,press home,press shift+end,type-text micro,wait-text micro,press cmd+s,wait-file '"$W4"'/shop-api/src/orders.py,press ctrl+q,wait-gone micro'
is 'ch4 beat 4 stages the path ⌘P f put on the line' "$(shape4 4)" \
  'adopt work,type-text work,wait-text work,type-text work,press cmd+p,press f,press 1,wait-text work,press enter,type-text work,wait-text work'
zsh $DEMO_ROOT/play 4 --dry-run 2>&1 | grep -q '^focus ' && bad 'ch4 moves focus without a key' || ok 'ch4 moves focus only with keys and clicks'
for k in cmd+p cmd+s ctrl+q enter; do
  grep -qF -- "$(demo_badge $k)" $C4/deck.md && ok "ch4 deck shows $k as $(demo_badge $k)" || bad "ch4 deck never shows $k as $(demo_badge $k)"
done
grep -q '⌘ click' $C4/deck.md && ok 'ch4 deck shows clicks as their badge' || bad 'ch4 deck never says ⌘ click'
```

(The beat 3 shape names the world path: the beat reads `${DEMO_WORLD:-$HOME/kitty-demo}`, hence `DEMO_WORLD=$W4` on the dry runs.)

Expected red: everything (no chapter 4).

- [ ] **Step 2: Chapter files.**

`instance`: `# This chapter runs in a kitty instance of its own (see play), in chapter 3's world.`
`layout`: `tall`
`requires`:
```
# kitty actions chapter 4 presses keys for (checked by play's pre-flight);
# the ⌘ click mapping is a mouse_map, which pre-flight doesn't read
kitten hint_menu.py
kitten micro_keys.py cmd+s
```

`session` (`chmod +x`):
```zsh
#!/usr/bin/env zsh
# session: write chapter 4's kitty session (see the chapter 4 spec).
#
#   session WORLD STATE -- DECK-CMD...
#
# One tab: the deck, and a shell in shop-api beside it. Chapter 3 leaves
# shop-api's NOTES.md changed (its tidy-up needs a dirty tree); this chapter
# restores it, so its git status lists only the file it fixes.

setopt err_exit
(( $# >= 4 )) && [[ $3 == -- ]] || { print -ru2 -- 'usage: session WORLD STATE -- DECK-CMD...'; exit 2 }
world=${1:a} state=${2:a}; shift 3
git -C $world/shop-api checkout -q -- NOTES.md
{
  print -r -- '# kitty session for chapter 4 (written by its session script)'
  print -r -- 'new_tab work'; print -r -- 'layout tall'; print -r -- "cd $world"
  print -r -- "launch --hold --var demo=deck ${(j: :)${(qq)@}}"
  print -r -- 'focus'
  print -r -- "cd $world/shop-api"
  print -r -- 'launch --var demo=work'
  print -r -- 'focus_tab 0'
} >| $state/session.kitty
```

Note: `focus` after the deck keeps it the active window; the work shell gets focus from the first ⌘ click (a click focuses the pane it lands on) — beat 1 clicks in it after typing `ls` into it with `type-text`, which needs no focus.

- [ ] **Step 3: `deck.md`** (9 slides):

```markdown
<!-- jump_to_middle -->

Working in a project
====================

A small fix in shop-api, start to
finish, without leaving the terminal.

Every key and click here is real:
watch the badge at the bottom.

<!-- end_slide -->

<!-- jump_to_middle -->

Two helpers
===========

<!-- incremental_lists: true -->

* ⌘ click opens a link: a file, a
  note, a directory
* ⌘P picks things off the screen

<!-- end_slide -->

<!-- jump_to_middle -->

⌘ click a note
==============

<!-- incremental_lists: true -->

* ls lists files as links
* Markdown opens rendered, in glow;
  q closes it
* Watch: ⌘ click NOTES.md

<!-- end_slide -->

<!-- jump_to_middle -->

⌘ click a directory
===================

<!-- incremental_lists: true -->

* The shell moves there: no cd to type
* Watch: ⌘ click src

<!-- end_slide -->

<!-- jump_to_middle -->

Open it at the line: ⌘P
=======================

<!-- incremental_lists: true -->

* rg finds the TODO
* ⌘P shows a menu of hints; n picks
  file:line and opens it in micro
* Watch: ⌘P, n, then the hint

<!-- end_slide -->

<!-- jump_to_middle -->

Fix it
======

<!-- incremental_lists: true -->

* Type over the TODO line
* ⌘S saves; ⌃Q quits micro
* Watch: the fix, ⌘S, ⌃Q

<!-- end_slide -->

<!-- jump_to_middle -->

Pick a path off the screen: ⌘P
==============================

<!-- incremental_lists: true -->

* git status shows the changed file
* f puts its path on the command
  line, quoted for the shell
* Watch: git add, ⌘P, f, the hint, ↩

<!-- end_slide -->

<!-- jump_to_middle -->

That's working in a project
===========================

<!-- incremental_lists: true -->

* ⌘ click: open a file, note or dir
* ⌘P n: open file:line in micro
* ⌘P f: insert a path from the screen
* ⌘P: also words, lines, hashes
* ⌘S / ⌃Q: save, quit in micro

<!-- end_slide -->

<!-- jump_to_middle -->

The helpers
===========

kitty kittens and a little zsh:
open_local.py · hint_menu.py
micro_keys.py · kitty-cd-link.zsh

github.com/garethrowlands/project-tools
```

- [ ] **Step 4: Beats.**

`00-intro.zsh`:
```zsh
# Beat 0: the premise, then the two helpers the chapter uses.
slide goto 1 'Working in a project'
beat-pause 6
slide goto 2 'Two helpers'
beat-pause 2
reveal '⌘ click opens a link' 3
reveal '⌘P picks things off the screen' 3
```

`01-notes.zsh`:
```zsh
# Beat 1: ls in shop-api lists its files as links; ⌘ click NOTES.md opens
# it rendered in glow (an overlay over the work pane), showing the to-do;
# q closes it.
slide goto 3 '⌘ click a note'
adopt work 'var:demo=work'
beat-pause 2
reveal 'ls lists files as links' 2.5
type-text work "clear; ls\r"
wait-text work 'NOTES.md'
reveal 'Markdown opens rendered' 3
reveal 'Watch: ⌘ click NOTES.md' 3
mouse glide-text work 'NOTES.md'
mouse click cmd
adopt glow 'cmdline:"(^|/)glow$"'
wait-text glow 'Retry-After'
beat-pause 4
press q
wait-gone glow
beat-pause 1
```

`02-dir.zsh`:
```zsh
# Beat 2: ⌘ click src in the same listing: the shell cds there (pwd proves
# it, since the prompt's look varies).
slide goto 4 '⌘ click a directory'
adopt work 'var:demo=work'
beat-pause 2
reveal 'The shell moves there' 3
reveal 'Watch: ⌘ click src' 3
mouse glide-text work 'src'
mouse click cmd
beat-pause 1
type-text work "pwd\r"
wait-text work 'shop-api/src'
beat-pause 2
```

`03-open.zsh`:
```zsh
# Beat 3: rg finds the one TODO; ⌘P's menu, n (file:line hints) and the
# hint's label open orders.py in micro at that line. Then the fix: select
# the line (Home, ⇧End), type over it, ⌘S, ⌃Q. The file on disk is checked,
# so an edit micro mangled (e.g. autoclose doubling a bracket) fails here.
slide goto 5 'Open it at the line'
adopt work 'var:demo=work'
beat-pause 2
reveal 'rg finds the TODO' 2.5
type-text work "clear; rg --no-heading TODO\r"
wait-text work 'TODO: return 429'
reveal '⌘P shows a menu of hints' 3.5
reveal 'Watch: ⌘P, n, then the hint' 3
press cmd+p
beat-pause 1.5
press n
beat-pause 1.5
# the one match gets the first hint label (rehearsal confirms)
press 1
adopt micro 'cmdline:"(^|/)micro$"'
wait-text micro 'TODO'
beat-pause 2
slide goto 6 'Fix it'
beat-pause 2
reveal 'Type over the TODO line' 2.5
reveal '⌘S saves; ⌃Q quits micro' 2.5
reveal 'Watch: the fix, ⌘S, ⌃Q' 3
press home
press shift+end
type-text micro 'return too_many_requests(retry_after=60)'
wait-text micro 'too_many_requests'
beat-pause 1.5
press cmd+s
wait-file ${DEMO_WORLD:-$HOME/kitty-demo}/shop-api/src/orders.py 'return too_many_requests(retry_after=60)'
beat-pause 1.5
press ctrl+q
wait-gone micro
beat-pause 1
```

`04-stage.zsh`:
```zsh
# Beat 4: git status lists the changed file; with `git add ` typed, ⌘P f
# and the hint's label put its path on the command line; ↩ stages it.
slide goto 7 'Pick a path off the screen'
adopt work 'var:demo=work'
beat-pause 2
reveal 'git status shows the changed file' 2.5
type-text work "clear; git status --short\r"
wait-text work 'orders.py'
reveal 'f puts its path on the command' 3
reveal 'Watch: git add, ⌘P, f, the hint, ↩' 3
type-text work 'git add '
press cmd+p
beat-pause 1.5
press f
beat-pause 1.5
press 1
wait-text work 'git add orders.py'
beat-pause 1.5
press enter
type-text work "git status --short\r"
wait-text work 'M  orders.py'
beat-pause 2
```

`05-cheat.zsh`:
```zsh
# Beat 5: the cheat sheet, one item per key or click.
slide goto 8 "That's working in a project"
beat-pause 1.5
reveal '⌘ click: open a file' 1.5
reveal '⌘P n: open file:line' 1.5
reveal '⌘P f: insert a path' 1.5
reveal '⌘P: also words' 1.5
reveal '⌘S / ⌃Q: save, quit' 1.5
beat-pause 3
```

`06-closing.zsh`:
```zsh
# Beat 6: the closing slide: what the helpers are and where they live.
slide goto 9 'The helpers'
beat-pause 6
```

- [ ] **Step 5: Run the tests** — Expected: no FAIL lines. If a shape differs only because a verb the plan didn't foresee is needed, rule on it in the ledger and update the shape.
- [ ] **Step 6: Commit** — `git add -A kitty/demo && git commit -m "kitty demo: chapter 4, working in a project"`.

---

### Task 5: Docs

**Files:** `kitty/demo/README.md`, `CLAUDE.md`

- [ ] **Step 1:** README "Running": `kitty/demo/play 4                  # chapter 4: working in a project (its own kitty instance)`. "Chapters": instance chapters use the shared `world/build-world` and their own `session` script; a `claude` file marks a chapter that needs the recorded Claude sessions and an API key. Chapter 3 setup section: note chapter 4 needs none of its Claude steps.
- [ ] **Step 2:** `CLAUDE.md`: `(1 shaders, 2 windows, panes and tabs, 3 getting around projects, 4 working in a project)`.
- [ ] **Step 3:** Run the tests; commit `docs: chapter 4`.

---

### Task 6 (user): rehearsal

- [ ] Reload Hammerspoon (`stage.lua` changed).
- [ ] `play 4 --only 0`, then `--only 1` … `--only 4` (beats 1–4 each `adopt work` themselves; beat 3 needs beat 2's `cd`, so rehearse 2–4 with `--from 2`).
- [ ] Settle: the first hint label (`press 1`), micro's line selection (Home, ⇧End) and whether autoclose disturbs the typed fix, the glow overlay's command line for `adopt`.
- [ ] Full take with `--record`.
