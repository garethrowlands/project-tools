# kitty Demo Chapters Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn `kitty/demo/play` into a chapter runner (`play CHAPTER …`), move today's demo into chapter 1, and add chapter 2, "Windows, panes and tabs", driven by real keystrokes with an on-screen key badge.

**Architecture:** Chapters live in `kitty/demo/chapters/N-name/` (deck, beats, scene, optional `requires`); the shared machinery (`play`, `lib.zsh`, `card`, `stage.lua`, geometry) stays in `kitty/demo/`. New verbs post real keystrokes through Hammerspoon (`demoStage.press`), which also draws the badge; each press is followed by a check that it had its effect. Pre-flight checks kitty is frontmost and that the chapter's `requires` mappings exist in `kitty.conf` or its includes.

**Tech Stack:** zsh, jq, kitty 0.49.1 remote control, Hammerspoon (Lua: `hs.eventtap`, `hs.canvas`), presenterm 0.16.1.

**Spec:** `docs/superpowers/specs/2026-10-04-kitty-demo-chapters-design.md` (builds on `docs/superpowers/specs/2026-10-04-kitty-shader-demo-design.md`)

## Global Constraints

- Work on branch `kitty-demo-chapters`. Commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Never push.
- zsh tests in the existing style (`ok`/`bad`/`is`, `exit $fail`); run with `zsh kitty/demo/tests/demo-tests.zsh </dev/null` (stdin must not be a pipe: `rg` reads stdin otherwise).
- Narration: one state per slide, each slide shown before its change, with a pause to read. Slide text lines ≤ 40 characters in chapter 2 (the deck shares the tab with three panes).
- Badges: Mac modifier glyph order ⌃⌥⇧⌘; keys ← → ↑ ↓ ↩ ⇥, letters upper-case; shown ~1.2 s at the bottom centre.
- Hammerspoon reads `stage.lua` only on config load; after editing it the user reloads Hammerspoon (pre-flight already checks the mtime).
- The sandbox cannot reach kitty or Hammerspoon: steps marked **(manual)** are for the user.
- Shell writes under `.claude/skills/` are blocked; use the Edit tool there.

## Review Focus

1. **Running `play` the old way** (`play --only 3`, no chapter) must fail with the usage line, not run something unexpected. — Task 1 test "an option before the chapter is a usage error".
2. **A key that does nothing** (mapping changed, kitty not frontmost) must fail the beat promptly with the key named, not desynchronise the show. — Task 2 tests "press-focus fails when focus does not move", "press-new fails when no window appears".
3. **A keystroke that opens two windows** (or a stray window appearing meanwhile) must not be silently adopted. — Task 2 test "press-new fails on two new windows".
4. **A `kitty.conf` that includes other files** (micro-keys.conf holds the Cmd+S/Cmd+F fallbacks) must have its includes searched. — Task 3 test "mappings in included files count".
5. **Chapter 1 must behave exactly as before** after the move (scene paths, slide numbers, first-slide wait). — Task 1: the moved suite passes unchanged in substance, plus "chapter 1's deck title".

---

### Task 1: Chapters in `play`; chapter 1 moves

**Files:**
- Move: `kitty/demo/{deck.md,beats,scene}` → `kitty/demo/chapters/1-shaders/`
- Modify: `kitty/demo/play`, `kitty/demo/chapters/1-shaders/beats/{03-cursor,08-os-window,09-links}.zsh`, `kitty/demo/tests/demo-tests.zsh`

**Interfaces:**
- Produces: `play [CHAPTER [--from N | --only N] [--slow F] [--dry-run]]`; `demo_chapter_dir ARG` → chapter path (status 1 if none); `demo_deck_title DECK` → first setext title; global `DEMO_CHAPTER_DIR`. Beats reference scene files as `$DEMO_CHAPTER_DIR/scene/…`.

- [ ] **Step 1: Move chapter 1 and repoint its paths (tests first)**

```bash
cd kitty/demo
mkdir -p chapters/1-shaders
git mv deck.md beats scene chapters/1-shaders/
sed -i '' 's|\$DEMO_ROOT/scene|$DEMO_CHAPTER_DIR/scene|' chapters/1-shaders/beats/*.zsh
cd tests
sed -i '' -e 's|\$DEMO_ROOT/beats|$C1/beats|g' -e 's|\$DEMO_ROOT/deck.md|$C1/deck.md|g' \
  -e 's|\$DEMO_ROOT/scene|$C1/scene|g' -e 's|zsh \$DEMO_ROOT/play --|zsh $DEMO_ROOT/play 1 --|g' \
  -e 's|"\$DEMO_ROOT"'"'"'/scene/other-app.txt|"$C1"'"'"'/scene/other-app.txt|' demo-tests.zsh
```

Then in `demo-tests.zsh`, directly after the `DEMO_ROOT=${0:A:h:h}` line add `C1=$DEMO_ROOT/chapters/1-shaders`, and insert this section above the `# --- play ---` section's `source $DEMO_ROOT/play` line's following tests (i.e. after the `demo_already_running` tests):

```zsh
# chapters
is 'chapter by number'           "$(demo_chapter_dir 1)" $C1
is 'chapter by full name'        "$(demo_chapter_dir 1-shaders)" $C1
demo_chapter_dir 9 >/dev/null && bad 'unknown chapter accepted' || ok 'unknown chapter rejected'
is "chapter 1's deck title"      "$(demo_deck_title $C1/deck.md)" 'kitty, with shaders'
out=$(zsh $DEMO_ROOT/play 2>&1); st=$?
[[ $st == 0 && $out == *1-shaders* ]] && ok 'play alone lists the chapters' || bad "play alone: $st ${(q+)out}"
zsh $DEMO_ROOT/play 9 --dry-run >/dev/null 2>&1; is 'unknown chapter is a usage error' $? 2
zsh $DEMO_ROOT/play --only 3 >/dev/null 2>&1; is 'an option before the chapter is a usage error' $? 2
[[ $(zsh $DEMO_ROOT/play 1-shaders --dry-run --only 0 2>&1) == *"slide goto 1 'kitty, with shaders'"* ]] \
  && ok 'chapter by name dry-runs' || bad 'chapter by name does not dry-run'
```

- [ ] **Step 2: Run the suite; expect the new chapter tests and every `play 1 …` test to fail**

Run: `zsh kitty/demo/tests/demo-tests.zsh </dev/null | grep -v ^PASS`
Expected: FAILs from `demo_chapter_dir: command not found`, the chapter tests, and the dry-run shape tests (play doesn't take a chapter yet).

- [ ] **Step 3: Implement chapters in `play`**

Replace `demo_usage`, add the helpers after it, and change `demo_present`, `demo_direct` and `demo_play_main` as follows.

```zsh
demo_usage() {
  print -r -- 'usage: play [CHAPTER [--from N | --only N] [--slow FACTOR] [--dry-run]]'
}

# demo_chapter_dir ARG: the chapter directory for "2" or "2-windows".
demo_chapter_dir() {
  local d
  for d in $DEMO_ROOT/chapters/<->-*(N/n); do
    if [[ ${d:t} == $1 || ${${d:t}%%-*} == $1 ]]; then
      print -r -- $d
      return 0
    fi
  done
  return 1
}

# demo_deck_title DECK: the deck's first slide title (first setext heading);
# the director waits for it to know presenterm is up.
demo_deck_title() {
  awk 'prev != "" && /^=+$/ { print prev; exit } { prev = $0 }' $1
}
```

In `demo_present`: `presenterm $DEMO_ROOT/deck.md` → `presenterm $DEMO_CHAPTER_DIR/deck.md`.

In `demo_direct`: `wait-text deck 'kitty, with shaders'` → `wait-text deck "$(demo_deck_title $DEMO_CHAPTER_DIR/deck.md)"`.

At the top of `demo_play_main`, before the option loop:

```zsh
  if (( ! $# )); then
    print -r -- 'chapters:'
    local d
    for d in $DEMO_ROOT/chapters/<->-*(N/n); do print -r -- "  ${d:t}"; done
    return 0
  fi
  [[ $1 == (-h|--help) ]] && { demo_usage; return 0 }
  [[ $1 != -* ]] || { demo_usage >&2; return 2 }
  typeset -g DEMO_CHAPTER_DIR
  DEMO_CHAPTER_DIR=$(demo_chapter_dir $1) || { print -u2 "play: no chapter $1"; demo_usage >&2; return 2 }
  shift
```

and `demo_select_beats $DEMO_ROOT/beats` → `demo_select_beats $DEMO_CHAPTER_DIR/beats`. Update the header comment's usage line to match `demo_usage`.

- [ ] **Step 4: Run the suite**

Run: `zsh kitty/demo/tests/demo-tests.zsh </dev/null | grep -v ^PASS; echo $?`
Expected: no FAIL lines.

- [ ] **Step 5: Commit**

```bash
git add -A kitty/demo
git commit -m "kitty demo: chapters; the shader demo becomes chapter 1

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Real keystrokes and the key badge

**Files:**
- Modify: `kitty/demo/lib.zsh` (append), `kitty/demo/stage.lua`, `kitty/demo/tests/demo-tests.zsh`

**Interfaces:**
- Consumes: `demo_dry`, `demo_hs`, `demo_kitten`, `demo_poll`, `demo_err`, `demo_id`, `demo_deck_alive`, `DEMO_IDS`, `DEMO_CREATED`.
- Produces:
  - `demo_press_args KEYS` → the Lua arguments, e.g. `{"shift","cmd"}, "return", "⇧⌘↩"`; status 1 for an unknown modifier.
  - Verbs: `press KEYS`; `press-focus KEYS` (press, then wait until kitty's focused window changes); `press-new NAME KEYS` (exactly one new window → NAME, cleaned up); `press-reorders KEYS` (press, then wait until the deck tab's window order changes); `wait-layout NAME`; `wait-tabs N`.
  - Lua: `demoStage.press(mods, key, label)` → "ok".

- [ ] **Step 1: Write the failing tests**

Insert above `# --- card ---` (the stubs from the verbs section are in force there). The `ls` stub reads its JSON from a file so a press can change what kitty "has":

```zsh
# --- real keys ------------------------------------------------------------------
is 'press args: cmd+shift+enter' "$(demo_press_args cmd+shift+enter)" '{"shift","cmd"}, "return", "⇧⌘↩"'
is 'press args: ctrl+alt+z'      "$(demo_press_args ctrl+alt+z)"      '{"ctrl","alt"}, "z", "⌃⌥Z"'
is 'press args: ctrl+shift+tab'  "$(demo_press_args ctrl+shift+tab)"  '{"ctrl","shift"}, "tab", "⌃⇧⇥"'
is 'press args: cmd+right'       "$(demo_press_args cmd+right)"       '{"cmd"}, "right", "⌘→"'
demo_press_args hyper+x >/dev/null 2>&1 && bad 'unknown modifier accepted' || ok 'unknown modifier rejected'

reset_stubs
press cmd+t
is 'press posts the key with its badge' "$(grep press $T/hcalls)" 'return demoStage.press({"cmd"}, "t", "⌘T")'

# ls JSON helpers: one tab holding the given window ids, the first focused.
# Verbs call demo_hs inside $(...), a subshell, so the fake kitty state lives
# in a file ($T/ls.json) that a stubbed press can rewrite.
lsjson() {
  local -a w; local id f=true
  for id in "$@"; do w+=("{\"id\":$id,\"is_focused\":$f}"); f=false; done
  print -r -- "[{\"tabs\":[{\"layout\":\"${LAYOUT:-splits}\",\"windows\":[${(j:,:)w}]}]}]"
}
kls() { print -r -- "$1" >| $T/ls.json }
functions[orig_kitten]=$functions[demo_kitten]
functions[orig_hs]=$functions[demo_hs]
demo_kitten() { print -r -- "$*" >> $T/kcalls; [[ $1 == ls ]] && { cat $T/ls.json; return }; return 0 }
# AFTER: the ls JSON a press leaves behind (empty: the press changes nothing)
demo_hs() { print -r -- "$1" >> $T/hcalls; [[ $1 == *press* && -n $AFTER ]] && kls "$AFTER"; print ok }
reset_stubs

kls "$(lsjson 7 5 6)"; AFTER=$(lsjson 7 5 6 9)
press-new C cmd+shift+enter && ok 'press-new adopts the new window' || bad 'press-new failed'
is 'press-new names it and cleans it up' "$DEMO_IDS[C] ${DEMO_CREATED[-1]}" '9 9'
kls "$(lsjson 7 5 6 9)"; AFTER=$(lsjson 7 5 6 9 10 11)
press-new D cmd+shift+enter 2>$T/err && bad 'press-new fails on two new windows' || ok 'press-new fails on two new windows'
kls "$(lsjson 7 5 6 9)"; AFTER=''
press-new E cmd+shift+enter 2>$T/err && bad 'press-new without a new window accepted' || ok 'press-new fails when no window appears'
[[ $(<$T/err) == *'⇧⌘↩'* ]] && ok 'press-new failure names the key' || bad "press-new failure: $(<$T/err)"

# press-focus: focus must move
kls "$(lsjson 7 5 6)"; AFTER=$(lsjson 5 7 6)
press-focus cmd+right && ok 'press-focus sees focus move' || bad 'press-focus failed'
kls "$(lsjson 7 5 6)"; AFTER=''
press-focus cmd+right 2>/dev/null && bad 'press-focus accepted no move' || ok 'press-focus fails when focus does not move'

# press-reorders, wait-layout, wait-tabs
kls "$(lsjson 7 5 6)"; AFTER=$(lsjson 7 6 5)
press-reorders cmd+shift+right && ok 'press-reorders sees the order change' || bad 'press-reorders failed'
kls "$(LAYOUT=tall lsjson 7 5 6)"
wait-layout tall && ok 'wait-layout sees the layout' || bad 'wait-layout failed'
wait-layout grid 2>/dev/null && bad 'wait-layout accepted the wrong layout' || ok 'wait-layout times out on the wrong layout'
kls '[{"tabs":[{"layout":"splits","windows":[{"id":7,"is_focused":true}]},{"layout":"splits","windows":[{"id":6,"is_focused":true}]}]}]'
wait-tabs 2 && ok 'wait-tabs counts the tabs' || bad 'wait-tabs failed'
wait-tabs 3 2>/dev/null && bad 'wait-tabs accepted the wrong count' || ok 'wait-tabs times out on the wrong count'
AFTER=''
functions[demo_kitten]=$functions[orig_kitten]
functions[demo_hs]=$functions[orig_hs]
```

- [ ] **Step 2: Run to verify they fail**

Run: `zsh kitty/demo/tests/demo-tests.zsh </dev/null | grep -v ^PASS`
Expected: `demo_press_args: command not found`, `press: command not found`, etc.

- [ ] **Step 3: Implement in `lib.zsh`** (append)

```zsh
# demo_press_args KEYS: Lua arguments for demoStage.press from KEYS such as
# cmd+shift+enter: the modifiers, Hammerspoon's key name and the badge
# label, modifiers in Mac order (⌃⌥⇧⌘).
demo_press_args() {
  local -a parts=(${(s:+:)1}) mods
  local key=$parts[-1] m label=''
  local -A glyph=(ctrl ⌃ alt ⌥ shift ⇧ cmd ⌘)
  local -A hsname=(enter return)
  local -A keyglyph=(left ← right → up ↑ down ↓ enter ↩ return ↩ tab ⇥)
  for m in $parts[1,-2]; do
    [[ -n $glyph[$m] ]] || { print -ru2 -- "unknown modifier $m in $1"; return 1 }
  done
  for m in ctrl alt shift cmd; do
    if (( ${parts[1,-2][(Ie)$m]} )); then mods+=("\"$m\""); label+=$glyph[$m]; fi
  done
  label+=${keyglyph[$key]:-${(U)key}}
  print -r -- "{${(j:,:)mods}}, \"${hsname[$key]:-$key}\", \"$label\""
}

# press KEYS: Hammerspoon posts the real keystroke to the frontmost app
# (kitty), so the user's own mappings act, and shows its badge.
press() {
  demo_dry press "$@" && return 0
  demo_deck_alive || return
  local args; args=$(demo_press_args $1) || { demo_err "press $1: bad keys"; return 1 }
  [[ $(demo_hs "return demoStage.press($args)") == ok ]] || { demo_err "press $1 failed"; return 1 }
}

demo_badge() { demo_press_args $1 | sed 's/.*, "\(.*\)"$/\1/' }

demo_ls_ids()     { demo_kitten ls | jq -r '[.[].tabs[].windows[].id] | sort | .[]' }
demo_focused_id() { demo_kitten ls | jq -r '[.[].tabs[].windows[] | select(.is_focused)][0].id // empty' }
demo_tab_order()  { demo_kitten ls | jq -c --argjson d ${DEMO_IDS[deck]:-0} '[.[].tabs[] | select(any(.windows[]; .id == $d)) | .windows[].id]' }

# press-focus KEYS: press, then wait until kitty's focused window changes.
press-focus() {
  demo_dry press-focus "$@" && return 0
  local before; before=$(demo_focused_id)
  press $1 || return
  demo_poll "$(demo_badge $1) to move focus" demo_focus_differs "$before"
}
demo_focus_differs() { [[ $(demo_focused_id) != "$1" ]] }

# press-reorders KEYS: press, then wait until the deck tab's window order changes.
press-reorders() {
  demo_dry press-reorders "$@" && return 0
  local before; before=$(demo_tab_order)
  press $1 || return
  demo_poll "$(demo_badge $1) to move the pane" demo_order_differs "$before"
}
demo_order_differs() { [[ $(demo_tab_order) != "$1" ]] }

# press-new NAME KEYS: press KEYS, which opens a kitty window; adopt exactly
# one new window as NAME (and clean it up like any other).
press-new() {
  demo_dry press-new "$@" && return 0
  local name=$1 keys=$2
  local -a before after new
  before=(${(f)"$(demo_ls_ids)"})
  press $keys || return
  local i
  for (( i = 0; i < DEMO_TIMEOUT * 10; i++ )); do
    after=(${(f)"$(demo_ls_ids)"})
    new=(${after:|before})
    (( $#new )) && break
    demo_sleep 0.1
  done
  (( $#new == 1 )) || { demo_err "press-new $name: $(demo_badge $keys) opened ${#new} windows, not 1"; return 1 }
  DEMO_IDS[$name]=$new[1]
  DEMO_CREATED+=($new[1])
}

# wait-layout NAME: wait until the deck's tab uses layout NAME.
wait-layout() {
  demo_dry wait-layout "$@" && return 0
  demo_poll "layout $1" demo_layout_is $1
}
demo_layout_is() {
  [[ $(demo_kitten ls | jq -r --argjson d ${DEMO_IDS[deck]:-0} '.[].tabs[] | select(any(.windows[]; .id == $d)) | .layout') == $1 ]]
}

# wait-tabs N: wait until the deck's OS window has N tabs.
wait-tabs() {
  demo_dry wait-tabs "$@" && return 0
  demo_poll "$1 tabs" demo_tabs_are $1
}
demo_tabs_are() {
  [[ $(demo_kitten ls | jq --argjson d ${DEMO_IDS[deck]:-0} '[.[] | select(any(.tabs[].windows[]; .id == $d)) | .tabs[]] | length') == $1 ]]
}
```

- [ ] **Step 4: Run the suite**

Run: `zsh kitty/demo/tests/demo-tests.zsh </dev/null | grep -v ^PASS; echo $?`
Expected: no FAIL lines.

- [ ] **Step 5: Add the badge and `press` to `stage.lua`**

After the `stopGlide` helper:

```lua
-- Key badge: the keys the director just pressed, at the bottom centre of
-- the screen, above kitty's tab bar; a new press replaces it.
local badge, badgeTimer

local function showBadge(label)
  if badgeTimer then badgeTimer:stop() end
  if badge then badge:delete() end
  local s = (main and main:screen() or hs.screen.mainScreen()):frame()
  local w, h = 240, 84
  badge = hs.canvas.new({x = s.x + (s.w - w) / 2, y = s.y + s.h - h - 70, w = w, h = h})
  badge:appendElements(
    {type = "rectangle", action = "fill", fillColor = {white = 0.08, alpha = 0.85},
     roundedRectRadii = {xRadius = 16, yRadius = 16}},
    {type = "text", frame = {x = 0, y = 12, w = w, h = h - 12},
     text = hs.styledtext.new(label, {font = {name = "Menlo", size = 40}, color = {white = 0.95},
                                      paragraphStyle = {alignment = "center"}})})
  badge:level(hs.canvas.windowLevels.overlay)
  badge:show()
  badgeTimer = hs.timer.doAfter(1.2, function() if badge then badge:hide(0.3) end end)
end

-- Post a real keystroke (mods e.g. {"shift","cmd"}, key e.g. "return") to
-- the frontmost app, showing `label` as the badge.
function M.press(mods, key, label)
  showBadge(label)
  hs.eventtap.keyStroke(mods, key, 20000)
  return "ok"
end
```

In `M.finish`, after `stopGlide()` add: `if badge then badge:delete(); badge = nil end`. In `M.selftest`, before its `return`, add: `showBadge("⌘→")`.

- [ ] **Step 6 (manual): reload Hammerspoon; from a kitty pane run** `hs -c 'return demoStage.press({"cmd"}, "t", "⌘T")'`. Expected: the badge appears at the bottom centre and kitty switches to the tall layout.

- [ ] **Step 7: Commit**

```bash
git add kitty/demo/lib.zsh kitty/demo/stage.lua kitty/demo/tests/demo-tests.zsh
git commit -m "kitty demo: real keystrokes with an on-screen key badge

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Pre-flight for keyboard chapters

**Files:**
- Modify: `kitty/demo/play`, `kitty/demo/tests/demo-tests.zsh`

**Interfaces:**
- Consumes: `DEMO_CHAPTER_DIR` (Task 1), `demo_hs`.
- Produces: `demo_conf_maps CONF` (every `map` line of CONF and the files it includes, tabs as spaces); `demo_missing_mappings REQUIRES CONF` (each required action with no `map` line, one per line); a chapter's optional `requires` file (one kitty action per line, `#` comments). When it exists, pre-flight also requires kitty to be the frontmost app.

- [ ] **Step 1: Write the failing tests** (in the `# --- play ---` section, after the chapter tests)

```zsh
mkdir -p $T/kconf
print -r -- $'map cmd+t goto_layout tall\nmap\tcmd+left\tneighboring_window left\ninclude extra.conf' >| $T/kconf/kitty.conf
print -r -- 'map cmd+f kitten micro_keys.py cmd+f find -- goto_layout fat' >| $T/kconf/extra.conf
print -r -- $'# needed\ngoto_layout tall\nneighboring_window left\ngoto_layout fat\ngoto_layout grid' >| $T/kconf/requires
is 'mappings in included files count' "$(demo_missing_mappings $T/kconf/requires $T/kconf/kitty.conf)" 'goto_layout grid'
print -r -- 'goto_layout tal' >| $T/kconf/requires2
is 'a mapping must match whole words' "$(demo_missing_mappings $T/kconf/requires2 $T/kconf/kitty.conf)" 'goto_layout tal'
```

- [ ] **Step 2: Run to verify they fail** — `demo_missing_mappings: command not found`.

- [ ] **Step 3: Implement in `play`** (before `demo_preflight`)

```zsh
# demo_conf_maps CONF: the map lines of a kitty config and the files it
# includes (relative includes resolve against the including file).
demo_conf_maps() {
  local conf=$1 line inc
  [[ -r $conf ]] || return 0
  while IFS= read -r line; do
    line=${line//$'\t'/ }
    case $line in
      'map '*) print -r -- "$line" ;;
      'include '*)
        inc=${~${line#include }}
        [[ $inc == /* ]] || inc=${conf:h}/$inc
        demo_conf_maps $inc ;;
    esac
  done < $conf
}

# demo_missing_mappings REQUIRES CONF: required actions with no map line.
demo_missing_mappings() {
  local maps req
  maps=$(demo_conf_maps $2)
  while IFS= read -r req; do
    [[ -z $req || $req == '#'* ]] && continue
    grep -qE -- " ${req}( |\$)" <<<$maps || print -r -- $req
  done < $1
}
```

In `demo_preflight`, before its last line `(( ok ))`, add:

```zsh
  if [[ -r $DEMO_CHAPTER_DIR/requires ]]; then
    [[ $(demo_hs 'return hs.application.frontmostApplication():bundleID()') == net.kovidgoyal.kitty ]] \
      || { print -u2 'play: kitty must be the frontmost app (this chapter presses real keys)'; ok=0 }
    local missing
    missing=$(demo_missing_mappings $DEMO_CHAPTER_DIR/requires ~/.config/kitty/kitty.conf)
    [[ -z $missing ]] || { print -u2 "play: kitty.conf has no mapping for: ${(j:, :)${(f)missing}}"; ok=0 }
  fi
```

- [ ] **Step 4: Run the suite** — no FAIL lines.

- [ ] **Step 5: Commit**

```bash
git add kitty/demo/play kitty/demo/tests/demo-tests.zsh
git commit -m "kitty demo: pre-flight checks the keys a chapter presses

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Chapter 2, "Windows, panes and tabs"

**Files:**
- Create: `kitty/demo/chapters/2-windows/{deck.md,requires}`, `kitty/demo/chapters/2-windows/beats/00-intro.zsh` … `08-finale.zsh`
- Test: `kitty/demo/tests/demo-tests.zsh` (new section at the end, before `exit $fail`)

**Interfaces:**
- Consumes: all verbs; `play 2`.
- Produces: the chapter. Layout order in beat 4 is T, F, S, G (ending on grid, so beat 5's zoom to stack is visible — a ruling against the spec's T F G S).

- [ ] **Step 1: Write the failing tests**

```zsh
# --- chapter 2 -----------------------------------------------------------------------
C2=$DEMO_ROOT/chapters/2-windows
slides2=("${(@ps:<!-- end_slide -->:)$(<$C2/deck.md)}")
is 'chapter 2 has 9 slides' $#slides2 9
is 'chapter 2 slides fit beside three panes' "$(awk 'length > 40' $C2/deck.md)" ''
for f in $C2/beats/*.zsh; do
  for line in ${(f)"$(grep '^slide goto' $f)"}; do
    words=(${(Q)${(z)line}})
    [[ $slides2[$words[3]] == *"$words[4]"* ]] && ok "ch2 ${f:t:r}: slide $words[3] says '$words[4]'" \
      || bad "ch2 ${f:t:r}: slide $words[3] doesn't say '$words[4]'"
  done
done
zsh $DEMO_ROOT/play 2 --dry-run >/dev/null 2>&1 && ok 'chapter 2 dry-runs' || bad 'chapter 2 fails its dry run'
shape() { zsh $DEMO_ROOT/play 2 --dry-run --only $1 2>&1 | grep -E '^(press|wait-layout|wait-tabs)' | paste -sd, - }
is 'ch2 beat 1 opens C with the real key'  "$(shape 1)" 'press-new C cmd+shift+enter'
is 'ch2 beat 2 hops focus'                 "$(shape 2)" 'press-focus cmd+right,press-focus cmd+down,press-focus cmd+left,press-focus cmd+up'
is 'ch2 beat 3 moves a pane'               "$(shape 3)" 'press-reorders cmd+shift+right,press-reorders cmd+shift+right'
is 'ch2 beat 4 switches layouts'           "$(shape 4)" 'press cmd+t,wait-layout tall,press cmd+f,wait-layout fat,press cmd+s,wait-layout stack,press cmd+g,wait-layout grid'
is 'ch2 beat 5 zooms and back'             "$(shape 5)" 'press ctrl+alt+z,wait-layout stack,press ctrl+alt+z,wait-layout grid'
is 'ch2 beat 6 detaches a pane'            "$(shape 6)" 'press cmd+shift+up,wait-tabs 2'
is 'ch2 beat 7 switches tabs'              "$(shape 7)" 'press-focus ctrl+tab,press-focus ctrl+shift+tab'
for req in new_window_with_cwd 'neighboring_window right' move_window_forward 'goto_layout grid' 'toggle_layout stack' 'detach_window new-tab'; do
  grep -qx -- $req $C2/requires && ok "chapter 2 requires $req" || bad "chapter 2 requires lacks $req"
done
```

- [ ] **Step 2: Run to verify they fail** — missing `$C2/deck.md`.

- [ ] **Step 3: Write `chapters/2-windows/requires`**

```
# kitty actions chapter 2 presses keys for (checked by play's pre-flight)
new_window_with_cwd
neighboring_window right
neighboring_window left
neighboring_window up
neighboring_window down
move_window_forward
goto_layout tall
goto_layout fat
goto_layout stack
goto_layout grid
toggle_layout stack
detach_window new-tab
```

- [ ] **Step 4: Write `chapters/2-windows/deck.md`** (9 slides; every line ≤ 40 characters)

```markdown
<!-- jump_to_middle -->

Windows, panes and tabs
=======================

Everything here is a real keypress:
watch the badge at the bottom.

<!-- end_slide -->

<!-- jump_to_middle -->

A new pane, same directory
==========================

Cmd+Shift+Enter splits off a shell
that starts where you are.

<!-- end_slide -->

<!-- jump_to_middle -->

Move focus with Cmd+arrows
==========================

The focused pane glows; the rest dim.

<!-- end_slide -->

<!-- jump_to_middle -->

Move the pane itself
====================

Cmd+Shift+← / → moves the focused
pane along.

<!-- end_slide -->

<!-- jump_to_middle -->

Layouts
=======

Cmd+T tall · Cmd+F fat
Cmd+S stack · Cmd+G grid

<!-- end_slide -->

<!-- jump_to_middle -->

Zoom one pane
=============

Ctrl+Option+Z fills the tab with
the focused pane, and back.

<!-- end_slide -->

<!-- jump_to_middle -->

A pane to its own tab
=====================

Cmd+Shift+↑ sends the focused pane
to a new tab (Cmd+Shift+↓ asks where).

<!-- end_slide -->

<!-- jump_to_middle -->

Switch tabs
===========

Ctrl+Tab and Ctrl+Shift+Tab.

<!-- end_slide -->

<!-- jump_to_middle -->

Panes, layouts and tabs
=======================

Cmd+Shift+Enter  new pane, same dir
Cmd+arrows       move focus
Cmd+Shift+←/→    move the pane
Cmd+T/F/S/G      layouts
Ctrl+Option+Z    zoom
Cmd+Shift+↑      pane to a new tab
Ctrl+Tab         switch tabs
```

- [ ] **Step 5: Write the beats** (`chapters/2-windows/beats/`)

`00-intro.zsh`:
```zsh
# Beat 0: the slides alone.
slide goto 1 'Windows, panes and tabs'
beat-pause 6
```

`01-new-pane.zsh`:
```zsh
# Beat 1: cards A and B give the tab some labelled panes; then the real
# Cmd+Shift+Enter opens C, a shell in the slides' directory.
slide goto 2 'same directory'
card ensure A $'Pane A' --location=vsplit
card ensure B $'Pane B' --location=hsplit --next-to=id:${DEMO_IDS[A]}
beat-pause 2.5
press-new C cmd+shift+enter
type-text C 'clear; pwd\r'
beat-pause 3
```

`02-focus.zsh`:
```zsh
# Beat 2: Cmd+arrows hop focus between panes; each press must move focus.
# The order depends on the split arrangement; rehearsal fixes the arrows.
slide goto 3 'Cmd+arrows'
focus deck
beat-pause 2
press-focus cmd+right
beat-pause 1.5
press-focus cmd+down
beat-pause 1.5
press-focus cmd+left
beat-pause 1.5
press-focus cmd+up
beat-pause 1.5
```

`03-move-pane.zsh`:
```zsh
# Beat 3: Cmd+Shift+→ moves the focused pane (card A) along the tab.
slide goto 4 'Move the pane itself'
focus A
beat-pause 2
press-reorders cmd+shift+right
beat-pause 1.5
press-reorders cmd+shift+right
beat-pause 1.5
```

`04-layouts.zsh`:
```zsh
# Beat 4: the four layouts, ending on grid so beat 5's zoom shows.
slide goto 5 'Layouts'
beat-pause 2.5
press cmd+t
wait-layout tall
beat-pause 2
press cmd+f
wait-layout fat
beat-pause 2
press cmd+s
wait-layout stack
beat-pause 2
press cmd+g
wait-layout grid
beat-pause 2
```

`05-zoom.zsh`:
```zsh
# Beat 5: Ctrl+Option+Z zooms the focused pane to the whole tab and back.
slide goto 6 'Zoom one pane'
beat-pause 2
press ctrl+alt+z
wait-layout stack
beat-pause 2
press ctrl+alt+z
wait-layout grid
beat-pause 1.5
```

`06-detach.zsh`:
```zsh
# Beat 6: Cmd+Shift+↑ sends card B to a new tab.
slide goto 7 'own tab'
focus B
beat-pause 2
press cmd+shift+up
wait-tabs 2
beat-pause 2.5
```

`07-tabs.zsh`:
```zsh
# Beat 7: Ctrl+Tab to B's tab and Ctrl+Shift+Tab back; each arrival glows.
slide goto 8 'Switch tabs'
beat-pause 2
press-focus ctrl+tab
beat-pause 2
press-focus ctrl+shift+tab
beat-pause 2
```

`08-finale.zsh`:
```zsh
# Beat 8: the cheat sheet; the panes close, the slides alone again.
slide goto 9 'Panes, layouts and tabs'
pane close A
pane close B
pane close C
beat-pause 6
```

Note for beat 6 with `--only 6`: `focus B` needs B; the run order supplies it. `--only` on beats 2–7 assumes beat 1's panes, so `card ensure` keeps A/B available only in beat 1 — rehearse those beats with `--from 1`.

- [ ] **Step 6: Run the suite** — no FAIL lines.

- [ ] **Step 7 (manual): rehearse** `play 2 --from 1`, then `play 2`. Fix beat 2's arrow sequence if a press-focus times out (the arrangement decides which arrows move focus), and any wait texts presenterm renders differently.

- [ ] **Step 8: Commit**

```bash
git add kitty/demo/chapters/2-windows kitty/demo/tests/demo-tests.zsh
git commit -m "kitty demo: chapter 2, windows, panes and tabs

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Docs

**Files:**
- Modify: `kitty/demo/README.md`, `CLAUDE.md`

- [ ] **Step 1: README** — replace the Running section's commands with:

```
kitty/demo/play                    # list the chapters
kitty/demo/play 1                  # chapter 1: shaders (~2 min)
kitty/demo/play 2                  # chapter 2: windows, panes and tabs
kitty/demo/play 2 --only 4         # one beat
kitty/demo/play 2 --from 4         # from beat 4 on
kitty/demo/play 1 --slow 2         # every pause doubled
kitty/demo/play 1 --dry-run        # print every verb, touch nothing
```

Add a "Chapters" paragraph: each chapter is `chapters/N-name/` with `deck.md`, `beats/`, optional `scene/` (beats use `$DEMO_CHAPTER_DIR/scene`) and optional `requires` (kitty actions whose mappings pre-flight checks; with it, kitty must also be frontmost). Add to the verb table:

```
| `press KEYS` | the real keystroke (e.g. `cmd+shift+enter`), with an on-screen badge |
| `press-focus KEYS` / `press-reorders KEYS` | press, then wait for focus / the pane order to change |
| `press-new NAME KEYS` | press, adopt the one new window as NAME |
| `wait-layout NAME` / `wait-tabs N` | readiness after a layout or tab key |
```

- [ ] **Step 2: CLAUDE.md** — in the kitty/demo architecture bullet, change "`kitty/demo/play`: the self-running, screen-recordable show-off of the kitty shaders" to "`kitty/demo/play`: self-running, screen-recordable chapters showing off the kitty setup (1 shaders, 2 windows, panes and tabs)".

- [ ] **Step 3: Run the suite; commit**

```bash
zsh kitty/demo/tests/demo-tests.zsh </dev/null | grep -c ^FAIL   # expect 0
git add kitty/demo/README.md CLAUDE.md
git commit -m "kitty demo: document chapters and the keystroke verbs

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
