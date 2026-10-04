# kitty demo chapter 3 "Getting around projects" Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `kitty/demo/play 3` records a ~1–2 min video of switch-project, the window switcher, tidy-windows, `ide` and `project-web`, played in a kitty instance of its own against a staged world.

**Architecture:** A new chapter directory (`chapters/3-projects/`) brings a `build-world` script (repos, zoxide db, zdotdir, kitty session file, Claude transcript titles) and a one-time `setup-claude`. `play` gains an instance mode: the outer `play 3` builds the world and starts a second kitty on that session; the session's deck window runs `play 3 --inside`, which directs as before. `lib.zsh` gains verbs to find windows the session or a tool opened, and `stage.lua` tiles and closes the launcher's app.

**Tech Stack:** zsh, kitty 0.49 remote control and session files, Hammerspoon (Lua), presenterm, git, zoxide, Claude Code CLI, jq.

**Spec:** `docs/superpowers/specs/2026-10-04-kitty-demo-chapter-3-design.md`

## Global Constraints

- Staged repos live in `${DEMO_WORLD:-$HOME/kitty-demo}`; never touch that directory unless it is absent or holds `.kitty-demo-world`.
- The Claude profile is `${CLAUDE_DEMO_DIR:-$HOME/.claude-demo}`; it must stay in `$HOME` with a `.claude` prefix (`bin/window-list` and `advise` glob `~/.claude*`).
- Fixed titles, verbatim: `Add rate limiting to orders endpoint` (shop-api), `Move Terraform state to S3` (infra).
- `blog`'s `origin` is `https://github.com/garethrowlands/project-tools.git`; the other repos' is `git@example.com:demo/<name>.git`. Nothing is ever pushed or fetched.
- The instance runs with `--listen-on unix:$DEMO_STATE/kitty.sock`, `-o confirm_os_window_close=0`, `-o macos_quit_when_last_window_closed=yes`, `--session $DEMO_STATE/session.kitty`, and none of the outer kitty's `KITTY_*` variables.
- Style rules from chapters 1–2: one state per slide, slide before its change; every focus change from a real keystroke with its badge (no `focus` verb in chapter 3 beats); slide lines ≤ 40 characters; slide lists one `* ` item per line.
- No changes to the project tools themselves (`zsh/bin/*`, `zsh/functions/*`, `python/tidy-windows-advise/*`).
- Tests: `zsh kitty/demo/tests/demo-tests.zsh </dev/null` (stdin must not be a pipe). New test sections go above the `# (later tasks add sections above this line)` marker.
- The sandbox can't reach kitty, Hammerspoon, `~/.claude-demo` or `~/kitty-demo`; steps marked **(user)** are run by the user, in kitty.

## Review Focus

1. The outer kitty's `KITTY_LISTEN_ON` leaking into the instance: the director would drive the user's real kitty, and tidy-windows could close the user's windows. Expect the instance's environment to have no outer `KITTY_*`, and the inner `play` to refuse to start unless `KITTY_LISTEN_ON` is the demo socket (tests in Task 5).
2. A real `~/kitty-demo` the user already has: expect `build-world` and pre-flight to refuse and name `DEMO_WORLD` (tests in Task 1 and Task 5).
3. Running chapter 3 before `setup-claude`, or twice in a row: expect a message naming `setup-claude`, and exactly one fixed `ai-title` per transcript however many runs (tests in Task 1).
4. Aborting mid-beat with VS Code or Edge tiled: expect cleanup to close the demo's app window or tab, restore an existing Edge window's frame, and give kitty its frame back (`finish` calls `closeTiled`; test in Task 3, frame restore checked in Task 7's rehearsal).
5. Edge already open with the user's own tabs: expect only the demo's tab to close and the window to return to where it was (Task 3's ⌘W-not-close code; checked in Task 7's rehearsal).

---

### Task 1: `build-world` — the staged world

**Files:**
- Create: `kitty/demo/chapters/3-projects/build-world`
- Test: `kitty/demo/tests/demo-tests.zsh` (new section `# --- chapter 3 world ---`)

**Interfaces:**
- Produces: `build-world [--no-claude] WORLD STATE -- DECK-CMD...` — exit 0 on success; 1 with a `build-world: …` message on stderr; 2 on usage errors. Writes `WORLD/{shop-api,web-app,infra,docs,blog}` and `WORLD/.kitty-demo-world`; `STATE/zoxide/` (zoxide db), `STATE/zdotdir/{.zshenv,.zshrc,.zprofile,.zlogin,world.zsh}`, `STATE/session.kitty`; deletes `STATE/projects.txt`. Reads `$CLAUDE_DEMO_DIR/kitty-demo-sessions` (lines `NAME SESSION-ID`) unless `--no-claude`.
- Session window user vars (`--var demo=…`): `deck`, `web-shell`, `shop-claude`, `shop-shell`, `infra-claude`, `docs-log`, `stray`. Tab titles: `web-app`, `shop-api`, `infra`, `docs`, `scratch`.

- [ ] **Step 1: Write the failing tests**

Add above the marker in `kitty/demo/tests/demo-tests.zsh`:

```zsh
# --- chapter 3 world -----------------------------------------------------------------
C3=$DEMO_ROOT/chapters/3-projects
W=$T/world3 S=$T/state3 CD=$T/claude3
mkdir -p $CD/projects/-x
print -r -- $'shop-api sid-shop\ninfra sid-infra' >| $CD/kitty-demo-sessions
print -r -- '{"type":"user","sessionId":"sid-shop"}' >| $CD/projects/-x/sid-shop.jsonl
print -r -- '{"type":"user","sessionId":"sid-infra"}' >| $CD/projects/-x/sid-infra.jsonl
bw() { CLAUDE_DEMO_DIR=$CD zsh $C3/build-world "$@" }
bw $W $S -- echo 'the deck' >/dev/null 2>$T/bw.err; is 'build-world succeeds' $? 0
for p in shop-api web-app infra docs blog; do
  [[ -z $(git -C $W/$p status --porcelain) ]] && ok "$p is clean" || bad "$p is dirty"
  is "$p has nothing unpushed" "$(git -C $W/$p rev-list --count @{u}..HEAD)" 0
done
is 'blog points at the real repo' "$(git -C $W/blog remote get-url origin)" https://github.com/garethrowlands/project-tools.git
is 'shop-api points at a fake host' "$(git -C $W/shop-api remote get-url origin)" git@example.com:demo/shop-api.git
(( $(git -C $W/docs log -1 --format=%ct) < EPOCHSECONDS - 30 * 86400 )) && ok 'docs looks stale' || bad 'docs commits are recent'
(( $(git -C $W/shop-api log -1 --format=%ct) > EPOCHSECONDS - 86400 )) && ok 'shop-api looks fresh' || bad 'shop-api commits are old'
is 'zoxide ranks the projects' "$(_ZO_DATA_DIR=$S/zoxide zoxide query --list | sed 's:.*/::' | paste -sd' ' -)" 'shop-api web-app infra docs blog'
[[ ! -e $S/projects.txt ]] && ok 'project cache is cleared' || bad 'project cache left behind'
grep -qx "launch --var demo=deck 'echo' 'the deck'" $S/session.kitty && ok 'deck window runs the deck command' || bad "deck line: $(grep demo=deck $S/session.kitty)"
grep -qx 'launch --var demo=shop-claude claude --resume sid-shop' $S/session.kitty && ok 'shop-api tab resumes its session' || bad 'no shop-api claude line'
grep -qx 'launch --var demo=infra-claude claude --resume sid-infra' $S/session.kitty && ok 'infra tab resumes its session' || bad 'no infra claude line'
is 'session tabs' "$(sed -n 's/^new_tab //p' $S/session.kitty | paste -sd' ' -)" 'web-app shop-api infra docs scratch'
grep -qx 'focus_tab 0' $S/session.kitty && ok 'session starts on the deck tab' || bad 'session does not focus tab 0'
is 'stray shell sits in shop-api' "$(grep -B1 'demo=stray' $S/session.kitty | head -1)" "cd $W/shop-api"
title() { jq -r 'select(.type == "ai-title") | .aiTitle' $CD/projects/-x/$1.jsonl }
is 'shop-api transcript gets its title' "$(title sid-shop)" 'Add rate limiting to orders endpoint'
is 'infra transcript gets its title' "$(title sid-infra)" 'Move Terraform state to S3'
bw $W $S -- echo 'the deck' >/dev/null 2>&1
is 'a second run adds no second title' "$(title sid-shop | wc -l | tr -d ' ')" 1
# the user's own .zshenv exports PROJECT_ROOTS unconditionally; the zdotdir wins
mkdir -p $T/home3; print -r -- 'export PROJECT_ROOTS=/wrong' >| $T/home3/.zshenv
is 'zdotdir overrides PROJECT_ROOTS' "$(env -i HOME=$T/home3 ZDOTDIR=$S/zdotdir /bin/zsh -c 'print -r -- $PROJECT_ROOTS')" $W
is 'zdotdir sets the Claude profile' "$(env -i HOME=$T/home3 ZDOTDIR=$S/zdotdir /bin/zsh -c 'print -r -- $CLAUDE_CONFIG_DIR')" $CD
mkdir -p $T/mine; print hi >| $T/mine/keep.txt
bw $T/mine $S -- true >/dev/null 2>$T/bw.err; is 'an unmarked world is refused' $? 1
[[ -f $T/mine/keep.txt && $(<$T/bw.err) == *DEMO_WORLD* ]] && ok 'refusal names DEMO_WORLD, touches nothing' || bad "refusal: $(<$T/bw.err)"
CLAUDE_DEMO_DIR=$T/nothing zsh $C3/build-world $T/w4 $T/s4 -- true >/dev/null 2>$T/bw.err
[[ $? == 1 && $(<$T/bw.err) == *setup-claude* ]] && ok 'no sessions file points at setup-claude' || bad "no sessions: $(<$T/bw.err)"
CLAUDE_DEMO_DIR=$T/nothing zsh $C3/build-world --no-claude $T/w5 $T/s5 -- true >/dev/null 2>&1
is '--no-claude builds without sessions' $? 0
zsh $C3/build-world $T/w6 >/dev/null 2>&1; is 'build-world without a deck command is a usage error' $? 2
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `zsh kitty/demo/tests/demo-tests.zsh </dev/null | grep -E '^FAIL' | head`
Expected: FAIL lines for `build-world succeeds` and onward (the script doesn't exist).

- [ ] **Step 3: Write `build-world`**

Create `kitty/demo/chapters/3-projects/build-world` (and `chmod +x`):

```zsh
#!/usr/bin/env zsh
# build-world: (re)build chapter 3's staged world (see the chapter 3 spec).
#
#   build-world [--no-claude] WORLD STATE -- DECK-CMD...
#
# WORLD (play passes ${DEMO_WORLD:-~/kitty-demo}) gets five small git repos;
# STATE (play's $DEMO_STATE) gets the zoxide db, zdotdir/ and session.kitty,
# whose deck window runs DECK-CMD. Unless --no-claude, the two Claude Code
# sessions named in $CLAUDE_DEMO_DIR/kitty-demo-sessions (setup-claude
# writes it) get their fixed ai-title. WORLD is only ever replaced if it is
# absent or carries the .kitty-demo-world marker.

setopt err_exit pipe_fail
zmodload zsh/datetime

fail()  { print -ru2 -- "build-world: $*"; exit 1 }
usage() { print -ru2 -- 'usage: build-world [--no-claude] WORLD STATE -- DECK-CMD...'; exit 2 }

claude=1
[[ ${1:-} == --no-claude ]] && { claude=0; shift }
(( $# >= 4 )) && [[ $3 == -- ]] || usage
world=${1:A} state=${2:A}; shift 3
claude_dir=${CLAUDE_DEMO_DIR:-$HOME/.claude-demo}
marker=$world/.kitty-demo-world

PROJECTS=(shop-api web-app infra docs blog)
# zoxide visits per project: the order the picker ranks them in
typeset -A VISITS=(shop-api 9 web-app 7 infra 5 docs 3 blog 1)
typeset -A WORK=(shop-api 'Orders endpoint' web-app 'Landing page' infra 'Terraform skeleton'
                 docs 'Release runbook' blog 'First post')
typeset -A TITLES=(shop-api 'Add rate limiting to orders endpoint' infra 'Move Terraform state to S3')
typeset -A SID

# Checks first, so a refusal leaves everything as it was.
[[ ! -e $world || -e $marker ]] \
  || fail "$world exists and isn't a kitty demo world; move it or set DEMO_WORLD"
if (( claude )); then
  sessions=$claude_dir/kitty-demo-sessions
  [[ -r $sessions ]] || fail "no $sessions: log in once with CLAUDE_CONFIG_DIR=$claude_dir claude, then run ${0:A:h}/setup-claude"
  while read -r name id; do
    [[ -n $name && $name != '#'* ]] && SID[$name]=$id
  done < $sessions
  for p in ${(k)TITLES}; do
    [[ -n ${SID[$p]:-} ]] || fail "$sessions names no $p session; run ${0:A:h}/setup-claude again"
  done
fi

# make_repo NAME ORIGIN EPOCH: a clean repo with two commits at EPOCH whose
# main tracks origin/main at HEAD, so nothing looks unpushed.
make_repo() {
  local dir=$world/$1 when="$3 +0000"
  rm -rf $dir && mkdir -p $dir
  git -C $dir init -q -b main
  print -r -- "# $1" >| $dir/README.md
  git -C $dir add -A
  GIT_AUTHOR_DATE=$when GIT_COMMITTER_DATE=$when \
    git -C $dir -c user.name=Demo -c user.email=demo@example.com commit -q -m 'Initial commit'
  print -r -- "$WORK[$1]" >| $dir/NOTES.md
  git -C $dir add -A
  GIT_AUTHOR_DATE=$when GIT_COMMITTER_DATE=$when \
    git -C $dir -c user.name=Demo -c user.email=demo@example.com commit -q -m $WORK[$1]
  git -C $dir remote add origin $2
  git -C $dir update-ref refs/remotes/origin/main HEAD
  git -C $dir branch -q --set-upstream-to=origin/main main
}

mkdir -p $world $state
: >| $marker
for p in $PROJECTS; do
  url=git@example.com:demo/$p.git
  [[ $p == blog ]] && url=https://github.com/garethrowlands/project-tools.git
  when=$EPOCHSECONDS
  [[ $p == docs ]] && when=$(( EPOCHSECONDS - 42 * 86400 ))
  make_repo $p $url $when
done

# zoxide: a fresh db, more visits for the projects the picker should rank first
rm -rf $state/zoxide && mkdir -p $state/zoxide
for p in $PROJECTS; do
  repeat $VISITS[$p] _ZO_DATA_DIR=$state/zoxide zoxide add $world/$p
done
rm -f $state/projects.txt

# zdotdir: the user's own startup files, then the world on top (their
# .zshenv exports PROJECT_ROOTS unconditionally, so it must come after)
z=$state/zdotdir
mkdir -p $z
{
  print -r -- '# kitty demo chapter 3: the staged world (written by build-world)'
  print -r -- "export PROJECT_ROOTS=${(q)world} PROJECT_CACHE=${(q)state}/projects.txt"
  print -r -- "export _ZO_DATA_DIR=${(q)state}/zoxide CLAUDE_CONFIG_DIR=${(q)claude_dir}"
} >| $z/world.zsh
for f in .zshenv .zprofile .zshrc .zlogin; do
  {
    print -r -- "# kitty demo chapter 3: the user's own $f, then the staged world"
    print -r -- "[[ -r \$HOME/$f ]] && source \$HOME/$f"
    print -r -- "source ${(q)z}/world.zsh"
  } >| $z/$f
done

# the session: five tabs, every window tagged with a demo= user var
{
  print -r -- '# kitty session for chapter 3 (written by build-world)'
  print -r -- 'new_tab web-app'; print -r -- 'layout tall'; print -r -- "cd $world/web-app"
  print -r -- "launch --var demo=deck ${(j: :)${(qq)@}}"
  print -r -- 'focus'
  print -r -- 'launch --var demo=web-shell'
  print -r -- 'new_tab shop-api'; print -r -- 'layout tall'; print -r -- "cd $world/shop-api"
  print -r -- "launch --var demo=shop-claude claude --resume ${SID[shop-api]:-none}"
  print -r -- 'launch --var demo=shop-shell'
  print -r -- 'new_tab infra'; print -r -- 'layout tall'; print -r -- "cd $world/infra"
  print -r -- "launch --var demo=infra-claude claude --resume ${SID[infra]:-none}"
  print -r -- 'new_tab docs'; print -r -- 'layout tall'; print -r -- "cd $world/docs"
  print -r -- 'launch --var demo=docs-log git log'
  print -r -- 'new_tab scratch'; print -r -- 'layout tall'; print -r -- "cd $world/shop-api"
  print -r -- 'launch --var demo=stray'
  print -r -- 'focus_tab 0'
} >| $state/session.kitty

# the fixed titles, appended once: bin/window-list shows the last ai-title
if (( claude )); then
  for p in ${(k)TITLES}; do
    t=$(find $claude_dir/projects -mindepth 2 -maxdepth 2 -name "$SID[$p].jsonl" -print -quit 2>/dev/null)
    [[ -n $t ]] || fail "no transcript for $p's session $SID[$p] under $claude_dir/projects"
    last=$(jq -r 'select(.type == "ai-title") | .aiTitle' $t | tail -1)
    [[ $last == $TITLES[$p] ]] \
      || jq -cn --arg t $TITLES[$p] --arg s $SID[$p] '{type: "ai-title", aiTitle: $t, sessionId: $s}' >> $t
  done
fi
```

Note the session lines ending `${SID[…]:-none}` only matter with `--no-claude`, where the session file is never used.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `zsh kitty/demo/tests/demo-tests.zsh </dev/null | grep -E '^FAIL'; echo "exit ${pipestatus[1]}"`
Expected: no FAIL lines. If `zoxide` is missing in the sandbox, report that rather than skipping the test.

- [ ] **Step 5: Commit**

```bash
git add kitty/demo/chapters/3-projects/build-world kitty/demo/tests/demo-tests.zsh
git commit -m "kitty demo: chapter 3's staged world (build-world)"
```

---

### Task 2: `setup-claude` and the Claude spike (gate)

**Files:**
- Create: `kitty/demo/chapters/3-projects/setup-claude`
- Test: `kitty/demo/tests/demo-tests.zsh` (append to `# --- chapter 3 world ---`)

**Interfaces:**
- Consumes: `build-world --no-claude WORLD STATE -- true` (Task 1).
- Produces: `$CLAUDE_DEMO_DIR/kitty-demo-sessions`, lines `shop-api <id>` then `infra <id>`.

- [ ] **Step 1: Write the failing test** (a fake `claude` on PATH records where it ran)

```zsh
mkdir -p $T/bin3 $T/cd3
print -r -- '#!/bin/zsh
print -r -- "{\"session_id\":\"sid-${PWD:t}\",\"result\":\"ok\"}"' >| $T/bin3/claude
chmod +x $T/bin3/claude
PATH=$T/bin3:$PATH CLAUDE_DEMO_DIR=$T/cd3 DEMO_WORLD=$T/w7 TMPDIR=$T/tmp3 \
  zsh $C3/setup-claude >/dev/null 2>$T/sc.err; is 'setup-claude succeeds' $? 0
is 'setup-claude records both sessions' "$(<$T/cd3/kitty-demo-sessions)" $'shop-api sid-shop-api\ninfra sid-infra'
CLAUDE_DEMO_DIR=$T/absent zsh $C3/setup-claude >/dev/null 2>$T/sc.err
[[ $? == 1 && $(<$T/sc.err) == *'claude'* ]] && ok 'setup-claude asks for a login first' || bad "setup-claude without profile: $(<$T/sc.err)"
```

- [ ] **Step 2: Run to verify it fails** — `zsh kitty/demo/tests/demo-tests.zsh </dev/null | grep -E '^FAIL'`; expected FAIL `setup-claude succeeds`.

- [ ] **Step 3: Write `setup-claude`** (`chmod +x`)

```zsh
#!/usr/bin/env zsh
# setup-claude: record chapter 3's two Claude Code conversations, once.
#
# First log in to the demo profile (a separate login, kept in ~/.claude-demo):
#   CLAUDE_CONFIG_DIR=~/.claude-demo claude      (log in, then /exit)
# Then run this. It builds the staged world, asks one question in shop-api
# and one in infra (claude -p: a few cents) and writes their session ids to
# ~/.claude-demo/kitty-demo-sessions, which build-world reads on every run.

setopt err_exit pipe_fail
here=${0:A:h}
claude_dir=${CLAUDE_DEMO_DIR:-$HOME/.claude-demo}
world=${DEMO_WORLD:-$HOME/kitty-demo}
state=${TMPDIR:-/tmp}/kitty-demo

[[ -d $claude_dir ]] || { print -ru2 -- "setup-claude: log in first: CLAUDE_CONFIG_DIR=$claude_dir claude"; exit 1 }
zsh $here/build-world --no-claude $world $state -- true

typeset -A PROMPT=(
  shop-api 'Outline, in three short bullets, how you would add rate limiting to the orders endpoint. Do not change any files.'
  infra    'Outline, in three short bullets, how you would move this Terraform state to S3. Do not change any files.'
)
out=$claude_dir/kitty-demo-sessions
: >| $out.tmp
for p in shop-api infra; do
  id=$(cd $world/$p && CLAUDE_CONFIG_DIR=$claude_dir claude -p --output-format json $PROMPT[$p] | jq -r '.session_id // empty')
  [[ -n $id ]] || { print -ru2 -- "setup-claude: claude gave no session id for $p"; rm -f $out.tmp; exit 1 }
  print -r -- "$p $id" >> $out.tmp
done
mv -f $out.tmp $out
print -r -- "recorded in $out:"; cat $out
```

- [ ] **Step 4: Run tests** — expect no FAIL lines.

- [ ] **Step 5: Commit**

```bash
git add kitty/demo/chapters/3-projects/setup-claude kitty/demo/tests/demo-tests.zsh
git commit -m "kitty demo: setup-claude records chapter 3's two conversations"
```

- [ ] **Step 6 (user): the spike.** Ask the user to run, in a kitty pane:

```
CLAUDE_CONFIG_DIR=~/.claude-demo claude          # log in, then /exit
kitty/demo/chapters/3-projects/setup-claude
kitty/demo/chapters/3-projects/build-world ~/kitty-demo $TMPDIR/kitty-demo -- true
cat ~/.claude-demo/kitty-demo-sessions
```

Then in a new kitty tab: `cd ~/kitty-demo/shop-api && CLAUDE_CONFIG_DIR=~/.claude-demo claude --resume <shop-api id>`. In another pane: `zsh/bin/window-list '' $(mktemp) | grep -i 'rate limiting'`. Then `/exit` the claude pane and run `jq -r 'select(.type=="ai-title")|.aiTitle' ~/.claude-demo/projects/*/<id>.jsonl | tail -1`.

Pass when: (a) the resumed pane shows the recorded conversation and nothing is sent (no spinner, no new reply); (b) `window-list` prints `[Add rate limiting to orders endpoint]` for that window; (c) after `/exit` the last ai-title is still the fixed one. **If any check fails, stop: report what happened and revise the spec with the user before Task 3.**

---

### Task 3: verbs for session windows, and tiling the launcher's app

**Files:**
- Modify: `kitty/demo/lib.zsh` (after `wait-own-tab`; `stage()`; `demo_press_args` key glyphs)
- Modify: `kitty/demo/stage.lua` (new block after `M.closeOther`; `M.finish`)
- Test: `kitty/demo/tests/demo-tests.zsh` (new section `# --- chapter 3 verbs ---`)

**Interfaces:**
- Produces (zsh verbs, each prints itself under `DEMO_DRY=1`):
  - `adopt NAME MATCH` → sets `DEMO_IDS[NAME]`; not added to `DEMO_CREATED`.
  - `wait-gone NAME` → unsets `DEMO_IDS[NAME]` once its window is gone.
  - `wait-in-tab NAME TITLE`, `wait-tab TITLE`.
  - `stage tile-next BUNDLE TITLE`, `stage wait-tiled` (polls up to 30 s), `stage close-tiled`.
- Produces (Lua): `demoStage.tileNext(bundle, titlePart)`, `demoStage.tiledPlaced()` → `"ok"|"not yet"`, `demoStage.closeTiled()`.
- `press escape` → badge `⎋`.

- [ ] **Step 1: Write the failing tests**

```zsh
# --- chapter 3 verbs ------------------------------------------------------------------
reset_stubs
KLSJSON='[{"tabs":[{"title":"web-app","is_active":true,"windows":[{"id":7,"is_active":true}]},
                   {"title":"shop-api","is_active":false,"windows":[{"id":21,"is_active":true}]}]}]'
adopt stray 'var:demo=stray' 2>/dev/null && is 'adopt names a lone match' ${DEMO_IDS[stray]} 21 || bad 'adopt failed'
(( ${DEMO_CREATED[(Ie)21]} )) && bad 'adopted window would be closed at cleanup' || ok 'adopted window is not the demo'\''s to close'
KLSJSON='[{"tabs":[{"title":"a","windows":[{"id":1},{"id":2}]}]}]'
adopt two 'var:demo=x' 2>/dev/null && bad 'adopt took one of two matches' || ok 'adopt refuses two matches'
KLSJSON='[{"tabs":[{"title":"web-app","is_active":true,"windows":[{"id":7,"is_active":true}]},
                   {"title":"shop-api","is_active":false,"windows":[{"id":21,"is_active":true}]}]}]'
wait-in-tab stray shop-api 2>/dev/null && ok 'wait-in-tab sees the tab title' || bad 'wait-in-tab missed shop-api'
wait-in-tab stray scratch 2>/dev/null && bad 'wait-in-tab matched the wrong tab' || ok 'wait-in-tab times out on the wrong tab'
wait-tab web-app 2>/dev/null && ok 'wait-tab sees the active tab' || bad 'wait-tab missed web-app'
wait-tab shop-api 2>/dev/null && bad 'wait-tab matched an inactive tab' || ok 'wait-tab times out on an inactive tab'
DEMO_IDS[log]=33
wait-gone log 2>/dev/null && bad 'wait-gone passed while the window exists' || ok 'wait-gone waits for the window'
print 33 >> $T/dead
wait-gone log 2>/dev/null && [[ -z ${DEMO_IDS[log]} ]] && ok 'wait-gone forgets a closed window' || bad 'wait-gone failed on a closed window'
reset_stubs
stage tile-next com.microsoft.VSCode blog
grep -qF 'demoStage.tileNext("com.microsoft.VSCode", "blog")' $T/hcalls && ok 'stage tile-next arms Hammerspoon' || bad "tile-next: $(<$T/hcalls)"
HSREPLY=ok stage wait-tiled 2>/dev/null && ok 'stage wait-tiled passes once placed' || bad 'wait-tiled failed'
HSREPLY='not yet' DEMO_TIMEOUT_TILED=0.2 stage wait-tiled 2>/dev/null && bad 'wait-tiled passed unplaced' || ok 'wait-tiled times out'
stage close-tiled; grep -qF 'demoStage.closeTiled()' $T/hcalls && ok 'stage close-tiled' || bad 'close-tiled not called'
is 'escape badge' "$(demo_press_args escape)" '{}, "escape", "⎋"'
is 'section-sign badge' "$(demo_press_args cmd+§)" '{"cmd"}, "§", "⌘§"'
is 'adopt dry-runs' "$(DEMO_DRY=1 adopt x 'var:demo=x')" 'adopt x var:demo=x'
grep -q 'if tiled then M.closeTiled() end' $DEMO_ROOT/stage.lua && ok 'finish closes a tiled app' || bad 'finish leaves a tiled app open'
```

- [ ] **Step 2: Run to verify they fail** — `zsh kitty/demo/tests/demo-tests.zsh </dev/null | grep -E '^FAIL'`; expected FAILs for `adopt`, `wait-*`, `stage tile-next`, `escape badge`, `finish closes`.

- [ ] **Step 3: Add the zsh verbs** to `kitty/demo/lib.zsh`, after `demo_alone_in_tab`:

```zsh
# adopt NAME MATCH: wait until exactly one window matches MATCH (kitty match
# syntax, e.g. var:demo=stray or cmdline:(^|/)tidy-windows$) and call it
# NAME. Not added to the cleanup list: a session or a tool opened it.
adopt() {
  demo_dry adopt "$@" && { DEMO_IDS[$1]=dry-$1; return 0 }
  demo_poll "one window matching $2" demo_adopt_one $1 "$2"
}
demo_adopt_one() {
  local -a ids
  ids=(${(f)"$(demo_kitten ls --match "$2" 2>/dev/null | jq -r '.[].tabs[].windows[].id')"})
  (( $#ids == 1 )) || return 1
  DEMO_IDS[$1]=$ids[1]
}

# wait-gone NAME: wait until NAME's window has closed, then forget it.
wait-gone() {
  demo_dry wait-gone "$@" && { unset "DEMO_IDS[$1]"; return 0 }
  local id; id=$(demo_id $1) || return
  demo_poll "pane $1 to close" demo_window_gone $id || return
  unset "DEMO_IDS[$1]"
}
demo_window_gone() { ! demo_window_exists $1 }

# wait-in-tab NAME TITLE: wait until NAME's window is in the tab titled TITLE.
wait-in-tab() {
  demo_dry wait-in-tab "$@" && return 0
  local id; id=$(demo_id $1) || return
  demo_poll "pane $1 to be in tab $2" demo_tab_of_is $id "$2"
}
demo_tab_of_is() {
  [[ $(demo_kitten ls | jq -r --argjson w $1 '[.[].tabs[] | select(any(.windows[]; .id == $w)) | .title][0] // empty') == "$2" ]]
}

# wait-tab TITLE: wait until the active tab of the deck's OS window is TITLE.
wait-tab() {
  demo_dry wait-tab "$@" && return 0
  demo_poll "tab $1 to be active" demo_active_tab_is "$1"
}
demo_active_tab_is() {
  [[ $(demo_kitten ls | jq -r --argjson d ${DEMO_IDS[deck]:-0} '[.[] | select(any(.tabs[].windows[]; .id == $d))
    | .tabs[] | select(.is_active) | .title][0] // empty') == "$1" ]]
}
```

In `stage()`, extend the doc comment and the `case`:

```zsh
# stage tile-next BUNDLE TITLE: before a launcher key, arm Hammerspoon to
#   tile the app's window (title containing TITLE) on the right half.
# stage wait-tiled: wait (up to 30 s: an IDE starts slowly) until it has.
# stage close-tiled: close that window or tab and give kitty the screen.
```

```zsh
    tile-next)   call="demoStage.tileNext($(demo_lua_str $2), $(demo_lua_str $3))" ;;
    wait-tiled)  # an IDE can take a while to start; tests shorten it
                 local DEMO_TIMEOUT=${DEMO_TIMEOUT_TILED:-30}
                 demo_poll "the app's window to be tiled" demo_tiled_placed; return ;;
    close-tiled) call='demoStage.closeTiled()' ;;
```

and next to `demo_other_placed`:

```zsh
demo_tiled_placed() { [[ $(demo_hs 'return demoStage.tiledPlaced()') == ok ]] }
```

In `demo_press_args`, add escape to the glyph map: `local -A keyglyph=(left ← right → up ↑ down ↓ enter ↩ return ↩ tab ⇥ escape ⎋)`.

- [ ] **Step 4: Add the Lua side** to `kitty/demo/stage.lua`. Near the other locals at the top:

```lua
-- The app window a launcher key opened (VS Code, Edge), tiled beside kitty by
-- tileNext: {bundle, win, savedFrame (if it was already open), wasRunning}.
local EDGE = "com.microsoft.edgemac"
local tiled, tileTimer
```

After `M.closeOther`:

```lua
-- Arm a 10 ms watcher for a launcher key: once `bundle` is the frontmost app
-- and its focused window's title contains `titlePart`, kitty takes the left
-- half and that window the right. A window that was already open (an Edge
-- window the new tab landed in) has its frame saved for closeTiled.
function M.tileNext(bundle, titlePart)
  if not main then return "no pinned window" end
  if tileTimer then tileTimer:stop() end
  local app = hs.application.get(bundle)
  local before = {}
  for _, w in ipairs(app and app:allWindows() or {}) do before[w:id()] = true end
  tiled = {bundle = bundle, wasRunning = app ~= nil}
  local deadline = hs.timer.secondsSinceEpoch() + 30
  tileTimer = hs.timer.doEvery(0.01, function()
    local front = hs.application.frontmostApplication()
    local win = front and front:bundleID() == bundle and front:focusedWindow()
    if win and win:title():find(titlePart, 1, true) then
      tileTimer:stop(); tileTimer = nil
      local left, right = halves()
      if before[win:id()] then tiled.savedFrame = win:frame() end
      tiled.win = win
      main:setFrame(left, 0)
      win:setFrame(right, 0)
      return
    end
    if hs.timer.secondsSinceEpoch() > deadline then tileTimer:stop(); tileTimer = nil end
  end)
  return "ok"
end

function M.tiledPlaced()
  return (tiled and tiled.win) and "ok" or "not yet"
end

-- Put things back: Edge loses only the demo's tab (Cmd+W; the window may
-- hold the user's tabs) and an existing window gets its frame back; any
-- other app's window is closed. The app quits if the demo started it.
-- Kitty fills the screen and takes focus again.
function M.closeTiled()
  if tileTimer then tileTimer:stop(); tileTimer = nil end
  if not tiled then return "ok" end
  local t = tiled
  tiled = nil
  if t.win then
    if t.bundle == EDGE then
      t.win:focus()
      hs.eventtap.keyStroke({"cmd"}, "w", 20000, hs.application.get(t.bundle))
      if t.savedFrame then
        hs.timer.usleep(200000)
        t.win:setFrame(t.savedFrame, 0)
      end
    else
      t.win:close()
    end
  end
  if not t.wasRunning then
    local app = hs.application.get(t.bundle)
    if app then app:kill() end
  end
  if main then
    main:setFrame(main:screen():frame(), 0)
    main:focus()
  end
  return "ok"
end
```

In `M.finish`, after `if otherTitle then M.closeOther(otherTitle) end`, add:

```lua
  if tiled then M.closeTiled() end
```

- [ ] **Step 5: Run the tests** — `zsh kitty/demo/tests/demo-tests.zsh </dev/null | grep -E '^FAIL'`; expected none (the existing `stage.lua blocks balance` test covers the Lua).

- [ ] **Step 6: Commit**

```bash
git add kitty/demo/lib.zsh kitty/demo/stage.lua kitty/demo/tests/demo-tests.zsh
git commit -m "kitty demo: verbs for session windows; tile and close a launcher's app"
```

---

### Task 4: `play` instance mode

**Files:**
- Modify: `kitty/demo/play` (`demo_usage`, option parsing, `demo_preflight`, new `demo_preflight_instance`, `demo_instance_cmd`, `demo_run_instance`, `demo_play_main`)
- Modify: `kitty/demo/lib.zsh` (`DEMO_INSIDE` global; end of `demo_cleanup`)
- Test: `kitty/demo/tests/demo-tests.zsh` (new section `# --- instance mode ---`)

**Interfaces:**
- Consumes: `build-world WORLD STATE -- DECK-CMD...` (Task 1).
- Produces: `play CHAPTER [--from N | --only N] [--slow F] [--dry-run]` unchanged for users; `--inside` (internal); `demo_instance_cmd WORLD` sets `reply` to the full command (array); `DEMO_INSIDE=1` makes `demo_cleanup` close the deck's OS window last.

- [ ] **Step 1: Write the failing tests**

```zsh
# --- instance mode ---------------------------------------------------------------------
DEMO_STATE=$T/st9
demo_instance_cmd $T/w9
cmd=" ${reply[*]} "
for want in ' -u KITTY_LISTEN_ON ' ' -u KITTY_WINDOW_ID ' ' -u KITTY_PID ' " ZDOTDIR=$T/st9/zdotdir " \
            " --listen-on unix:$T/st9/kitty.sock " ' -o confirm_os_window_close=0 ' \
            ' -o macos_quit_when_last_window_closed=yes ' " --session $T/st9/session.kitty " " PROJECT_ROOTS=$T/w9 "; do
  [[ $cmd == *$want* ]] && ok "instance command has${want% }" || bad "instance command lacks${want% }: $cmd"
done
# the whole outer run, with build-world and kitty faked
mkdir -p $T/ch9/beats $T/bin9
print -r -- '' >| $T/ch9/instance
print -r -- 'print -r -- "$*" >| '$T'/bw9.args' >| $T/ch9/build-world
print -r -- '#!/bin/zsh
print -r -- "$ZDOTDIR|${KITTY_LISTEN_ON:-unset}|$*" >| '$T'/kitty9.args' >| $T/bin9/kitty
chmod +x $T/bin9/kitty
( DEMO_CHAPTER_DIR=$T/ch9 DEMO_WORLD=$T/w9 KITTY_LISTEN_ON=unix:/outer PATH=$T/bin9:$PATH demo_run_instance --from 2 )
is 'outer run builds the world with an inner play' "$(<$T/bw9.args)" "$T/w9 $T/st9 -- $DEMO_ROOT/play ch9 --inside --from 2"
[[ $(<$T/kitty9.args) == "$T/st9/zdotdir|unset|"*"--session $T/st9/session.kitty"* ]] \
  && ok 'outer run starts kitty without the outer socket' || bad "kitty ran with: $(<$T/kitty9.args)"
# the inner play refuses any socket but the demo's
KITTY_LISTEN_ON=unix:/Users/x/.config/kitty/kitty-1.sock demo_inside_socket_ok 2>/dev/null \
  && bad 'inner play accepted the outer kitty' || ok 'inner play refuses the outer kitty'
KITTY_LISTEN_ON=unix:$T/st9/kitty.sock demo_inside_socket_ok && ok 'inner play accepts the demo socket' || bad 'inner play refused its own socket'
# cleanup inside the instance closes the deck's OS window, last
DEMO_STATE=$T/state; reset_stubs; DEMO_INSIDE=1
demo_cleanup
is 'inside cleanup closes the instance last' "$(tail -1 $T/kcalls)" 'close-os-window --match id:7'
DEMO_INSIDE=0
# pre-flight for an instance chapter
out=$(CLAUDE_DEMO_DIR=$T/none DEMO_WORLD=$T/mine DEMO_CHAPTER_DIR=$C3 demo_preflight_instance 2>&1)
[[ $out == *setup-claude* ]] && ok 'pre-flight points at setup-claude' || bad "pre-flight: $out"
[[ $out == *DEMO_WORLD* ]] && ok 'pre-flight refuses an unmarked world' || bad "pre-flight: $out"
zsh $DEMO_ROOT/play 1 --inside --dry-run >/dev/null 2>&1; is '--inside is accepted' $? 0
```

- [ ] **Step 2: Run to verify they fail** — expected FAILs from `instance command has…` onward.

- [ ] **Step 3: `lib.zsh`.** Add next to the other globals:

```zsh
typeset -g  DEMO_INSIDE=${DEMO_INSIDE:-0}     # 1: running in a chapter's own kitty instance
```

At the end of `demo_cleanup`, before `return 0`:

```zsh
  # In a chapter's own kitty instance, closing the deck's OS window quits the
  # instance (macos_quit_when_last_window_closed); it ends this process too,
  # so it comes last.
  (( DEMO_INSIDE )) && demo_kitten close-os-window --match id:$deck >/dev/null 2>&1
```

- [ ] **Step 4: `play`.** Update `demo_usage` text unchanged (`--inside` is internal; document it in the header comment instead):

```zsh
# A chapter with an `instance` file (chapter 3) runs in a kitty instance of
# its own: play builds the chapter's world, starts that kitty on the world's
# session, and the session's deck window runs `play CHAPTER --inside …`.
```

Add after `demo_preflight`:

```zsh
# demo_inside_socket_ok: inside an instance, kitten @ must reach the demo's
# own kitty, never the user's (tidy-windows there would close real windows).
demo_inside_socket_ok() {
  [[ $KITTY_LISTEN_ON == unix:$DEMO_STATE/kitty.sock* ]] \
    || { print -ru2 -- "play: --inside, but kitten @ would reach ${KITTY_LISTEN_ON:-no kitty}, not $DEMO_STATE/kitty.sock"; return 1 }
}

# What an instance chapter needs beyond demo_preflight's checks.
demo_preflight_instance() {
  local ok=1 cmd app
  local claude_dir=${CLAUDE_DEMO_DIR:-$HOME/.claude-demo} world=${DEMO_WORLD:-$HOME/kitty-demo}
  for cmd in kitty zoxide claude code gh uv git; do
    (( $+commands[$cmd] )) || { print -u2 "play: $cmd is not on PATH"; ok=0 }
  done
  [[ -n ${ANTHROPIC_API_KEY:-} ]] || { print -u2 'play: ANTHROPIC_API_KEY is not set (tidy-windows needs it)'; ok=0 }
  [[ -r $claude_dir/kitty-demo-sessions ]] \
    || { print -u2 "play: no Claude demo sessions: log in once with CLAUDE_CONFIG_DIR=$claude_dir claude, then run $DEMO_CHAPTER_DIR/setup-claude"; ok=0 }
  [[ ! -e $world || -e $world/.kitty-demo-world ]] \
    || { print -u2 "play: $world exists and isn't a kitty demo world (set DEMO_WORLD)"; ok=0 }
  for app in com.microsoft.VSCode com.microsoft.edgemac; do
    [[ $(demo_hs "return hs.application.pathForBundleID('$app') ~= nil" 2>/dev/null) == true ]] \
      || { print -u2 "play: $app is not installed"; ok=0 }
  done
  (( ok ))
}

# demo_instance_cmd WORLD: the command that starts the chapter's kitty, in
# $reply: the user's kitty.conf, the demo's own socket and session, the
# world's environment, and none of the outer kitty's variables.
demo_instance_cmd() {
  reply=(env -u KITTY_WINDOW_ID -u KITTY_LISTEN_ON -u KITTY_PID -u KITTY_PUBLIC_KEY
    ZDOTDIR=$DEMO_STATE/zdotdir PROJECT_ROOTS=$1 PROJECT_CACHE=$DEMO_STATE/projects.txt
    _ZO_DATA_DIR=$DEMO_STATE/zoxide CLAUDE_CONFIG_DIR=${CLAUDE_DEMO_DIR:-$HOME/.claude-demo}
    kitty --listen-on unix:$DEMO_STATE/kitty.sock --start-as=maximized
    -o confirm_os_window_close=0 -o macos_quit_when_last_window_closed=yes
    --session $DEMO_STATE/session.kitty)
}

# demo_run_instance OPTION...: build the world, start its kitty (whose deck
# runs play --inside with the same OPTIONs) and wait for it to quit.
demo_run_instance() {
  local world=${DEMO_WORLD:-$HOME/kitty-demo}
  mkdir -p $DEMO_STATE
  zsh $DEMO_CHAPTER_DIR/build-world $world $DEMO_STATE -- $DEMO_ROOT/play ${DEMO_CHAPTER_DIR:t} --inside "$@" || return 1
  demo_instance_cmd $world
  "${reply[@]}"
}
```

In `demo_preflight`, guard the "alone in its tab" check so it applies only to ordinary chapters:

```zsh
  if [[ ! -r $DEMO_CHAPTER_DIR/instance ]]; then
    [[ $(demo_kitten ls | jq "[.[].tabs[] | select(any(.windows[]; .id == $deck)) | .windows[]] | length") == 1 ]] \
      || { print -u2 'play: run me in a pane that is alone in its tab'; ok=0 }
  fi
```

In `demo_play_main`: declare `local inside=0` and `local -a passthrough`; after the chapter `shift`, set `passthrough=("$@")`, and add `--inside) inside=1; shift ;;` to the option `case`. Strip `--inside` from what's passed on: build `passthrough` from the parsed values instead of raw `$@`, i.e. after parsing:

```zsh
  passthrough=()
  (( from )) && passthrough+=(--from $from)
  [[ -n $only ]] && passthrough+=(--only $only)
  [[ $DEMO_SLOW != 1 ]] && passthrough+=(--slow $DEMO_SLOW)
```

After the `DEMO_DRY` branch and before `demo_preflight || return 1`:

```zsh
  if [[ -r $DEMO_CHAPTER_DIR/instance ]] && (( ! inside )); then
    demo_preflight && demo_preflight_instance || return 1
    demo_run_instance $passthrough
    return
  fi
  if (( inside )); then
    demo_inside_socket_ok || return 1
    DEMO_INSIDE=1
  fi
```

(`DEMO_INSIDE` must be set before the director subshell starts, so its cleanup sees it.)

- [ ] **Step 5: Run the tests** — expected no FAIL lines; chapters 1 and 2 still dry-run.

- [ ] **Step 6: Commit**

```bash
git add kitty/demo/play kitty/demo/lib.zsh kitty/demo/tests/demo-tests.zsh
git commit -m "kitty demo: play runs instance chapters in a kitty of their own"
```

---

### Task 5: chapter 3 deck and beats

**Files:**
- Create: `kitty/demo/chapters/3-projects/{deck.md,requires,layout,instance}`
- Create: `kitty/demo/chapters/3-projects/beats/{00-intro,01-jump,02-windows,03-tidy,04-new-project,05-ide,06-web,07-finale}.zsh`
- Test: `kitty/demo/tests/demo-tests.zsh` (new section `# --- chapter 3 ---`)

**Interfaces:**
- Consumes: `adopt`, `wait-gone`, `wait-in-tab`, `wait-tab`, `stage tile-next|wait-tiled|close-tiled` (Task 3); `press`, `press-new`, `type-text`, `wait-text`, `slide goto`, `beat-pause`, `pane close` (existing); session vars and tab titles (Task 1).

- [ ] **Step 1: Write the failing tests**

```zsh
# --- chapter 3 -----------------------------------------------------------------------
slides3=("${(@ps:<!-- end_slide -->:)$(<$C3/deck.md)}")
is 'chapter 3 has 8 slides' $#slides3 8
is 'chapter 3 slides fit beside a pane' "$(awk 'length > 40' $C3/deck.md)" ''
for f in $C3/beats/*.zsh; do
  for line in ${(f)"$(grep '^slide goto' $f)"}; do
    words=(${(Q)${(z)line}})
    [[ $slides3[$words[3]] == *"$words[4]"* ]] && ok "ch3 ${f:t:r}: slide $words[3] says '$words[4]'" \
      || bad "ch3 ${f:t:r}: slide $words[3] doesn't say '$words[4]'"
  done
done
zsh $DEMO_ROOT/play 3 --dry-run >/dev/null 2>&1 && ok 'chapter 3 dry-runs' || bad 'chapter 3 fails its dry run'
shape3() { zsh $DEMO_ROOT/play 3 --dry-run --only $1 2>&1 | grep -E '^(press|adopt|wait-|type-text|stage)' | awk '{print $1, $2}' | paste -sd, - }
is 'ch3 beat 1 jumps to shop-api and back' "$(shape3 1)" \
  'press cmd+§,adopt picker,wait-text picker,type-text picker,press enter,wait-tab shop-api,press ctrl+shift+tab,wait-tab web-app'
is 'ch3 beat 2 browses the switcher and leaves' "$(shape3 2)" \
  'press alt+tab,adopt switcher,wait-text switcher,press down,press down,press escape,wait-gone switcher'
is 'ch3 beat 3 tidies with the real key' "$(shape3 3)" \
  'adopt docs-log,adopt stray,press cmd+shift+w,adopt tidy,wait-text tidy,press enter,wait-gone docs-log,wait-in-tab stray'
is 'ch3 beat 4 opens blog beside the slides' "$(shape3 4)" \
  'press cmd+§,adopt picker,wait-text picker,type-text picker,press-new blog,type-text blog,wait-text blog'
is 'ch3 beat 5 tiles the IDE' "$(shape3 5)" 'stage tile-next,press cmd+i,stage wait-tiled,stage close-tiled'
is 'ch3 beat 6 tiles the browser' "$(shape3 6)" 'stage tile-next,press cmd+b,stage wait-tiled,stage close-tiled'
zsh $DEMO_ROOT/play 3 --dry-run 2>&1 | grep -q '^focus ' && bad 'ch3 moves focus without a key' || ok 'ch3 moves focus only with keys'
[[ -e $C3/instance ]] && ok 'chapter 3 runs in its own instance' || bad 'chapter 3 has no instance file'
is 'chapter 3 starts in the tall layout' "$(<$C3/layout)" tall
for tool in switch-project window tidy-windows ide project-web; do
  grep -qx -- "launch --type=overlay --cwd=current $tool" $C3/requires && ok "chapter 3 requires $tool" || bad "chapter 3 requires lacks $tool"
done
for k in ${(u)${(f)"$(zsh $DEMO_ROOT/play 3 --dry-run 2>&1 | awk '$1 == "press" {print $2} $1 == "press-new" {print $3}')"}}; do
  demo_press_args $k >/dev/null 2>&1 && ok "ch3 key $k has a badge" || bad "ch3 key $k has no badge"
done
body=$(print -r -- $slides3[8] | sed -n '/^=\{3,\}$/,$p' | grep -v '^=*$' | grep -v '^$')
is 'ch3 cheat sheet is one list item per key' "$(print -r -- $body | grep -vc '^\* ')" 0
```

- [ ] **Step 2: Run to verify they fail** — expected FAIL `chapter 3 has 8 slides` and onward.

- [ ] **Step 3: Write `deck.md`**

```markdown
<!-- jump_to_middle -->

Getting around projects
=======================

* One kitty window, a tab per project
* Every key is real: watch the badge

<!-- end_slide -->

<!-- jump_to_middle -->

Jump to a project: Cmd+§
========================

* Open projects first, then the rest,
  by how often you go there
* Type to filter, Enter to jump
* Ctrl+Shift+Tab comes back

<!-- end_slide -->

<!-- jump_to_middle -->

Every window, live: Option+Tab
==============================

* Claude Code panes show their
  conversation title
* The preview is the live screen
* Esc leaves you where you were

<!-- end_slide -->

<!-- jump_to_middle -->

Tidy up: Cmd+Shift+W
====================

* Claude reviews every window
* Stale ones: close
* Strays: back to their project's tab
* Enter applies; Tab unticks one

<!-- end_slide -->

<!-- jump_to_middle -->

A project with no window
========================

* Cmd+§, pick it, Enter
* A shell opens there, beside you

<!-- end_slide -->

<!-- jump_to_middle -->

Open the IDE: Cmd+I
===================

* VS Code or IntelliJ, on the
  project you're in

<!-- end_slide -->

<!-- jump_to_middle -->

The project's web page: Cmd+B
=============================

* Its GitHub or GitLab page
* An open tab is reused

<!-- end_slide -->

<!-- jump_to_middle -->

That's getting around
=====================

* Cmd+§ jump to a project
* Option+Tab every window
* Cmd+Shift+W tidy up
* Cmd+I the IDE
* Cmd+B the web page
```

- [ ] **Step 4: Write `requires`, `layout`, `instance`**

`requires`:
```
# kitty actions chapter 3 presses keys for (checked by play's pre-flight)
launch --type=overlay --cwd=current switch-project
launch --type=overlay --cwd=current window
launch --type=overlay --cwd=current tidy-windows
launch --type=overlay --cwd=current ide
launch --type=overlay --cwd=current project-web
```

`layout`: `tall`

`instance`:
```
# This chapter runs in a kitty instance of its own (see play): the window
# switcher and tidy-windows must see only the staged world's windows.
```

- [ ] **Step 5: Write the beats**

`beats/00-intro.zsh`:
```zsh
# Beat 0: the slides, and the five project tabs the session opened.
slide goto 1 'Getting around projects'
beat-pause 6
```

`beats/01-jump.zsh`:
```zsh
# Beat 1: Cmd+§ opens switch-project over the tab; "shop" narrows it to the
# open shop-api project and Enter jumps to that tab. Ctrl+Shift+Tab (the
# previous tab) brings the slides back.
slide goto 2 'Jump to a project'
beat-pause 4
press cmd+§
adopt picker 'cmdline:(^|/)switch-project$'
wait-text picker 'Project> '
beat-pause 1.5
type-text picker 'shop'
beat-pause 1.5
press enter
wait-tab shop-api
beat-pause 2.5
press ctrl+shift+tab
wait-tab web-app
beat-pause 1
```

`beats/02-windows.zsh`:
```zsh
# Beat 2: Option+Tab opens the window switcher: every window in this kitty,
# Claude Code panes labelled with their conversation title, the highlighted
# one previewed live. Two Downs move the highlight (rehearsal sets how many
# reach the Claude panes); Esc closes it where we were.
slide goto 3 'Every window, live'
beat-pause 4
press alt+tab
adopt switcher 'cmdline:(^|/)window$'
wait-text switcher 'ctrl-t: move to new tab'
beat-pause 2
press down
beat-pause 2
press down
beat-pause 2.5
press escape
wait-gone switcher
beat-pause 1
```

`beats/03-tidy.zsh`:
```zsh
# Beat 3: Cmd+Shift+W: tidy-windows asks Claude about every window (a real
# API call, hence the long wait) and pre-selects what it suggests; Enter
# applies it. Staged so the idle git log in docs is closed and the stray
# shop-api shell in "scratch" moves to shop-api's tab: both tabs leave the
# bar. If the model keeps docs-log, this beat fails: run the take again.
slide goto 4 'Tidy up'
adopt docs-log 'var:demo=docs-log'
adopt stray 'var:demo=stray'
beat-pause 4
press cmd+shift+w
adopt tidy 'cmdline:(^|/)tidy-windows$'
DEMO_TIMEOUT=30 wait-text tidy 'enter: apply marked'
beat-pause 3
press enter
wait-gone docs-log
wait-in-tab stray shop-api
beat-pause 3
```

`beats/04-new-project.zsh`:
```zsh
# Beat 4: blog has no window yet: Cmd+§, "blog", Enter opens a shell there,
# in this tab beside the slides (switch-project's Enter launches a window in
# the current tab). It shows where it started.
slide goto 5 'no window'
beat-pause 4
press cmd+§
adopt picker 'cmdline:(^|/)switch-project$'
wait-text picker 'Project> '
type-text picker 'blog'
beat-pause 1.5
press-new blog enter
type-text blog "clear; pwd\r"
wait-text blog 'kitty-demo/blog'
beat-pause 3
```

`beats/05-ide.zsh`:
```zsh
# Beat 5: Cmd+I opens the focused pane's project (blog, from beat 4) in its
# IDE. Hammerspoon tiles VS Code on the right half as it appears, kitty on
# the left, then closes it and gives kitty the screen back.
slide goto 6 'Open the IDE'
beat-pause 4
stage tile-next com.microsoft.VSCode blog
press cmd+i
stage wait-tiled
beat-pause 3
stage close-tiled
beat-pause 1.5
```

`beats/06-web.zsh`:
```zsh
# Beat 6: Cmd+B opens blog's web page (its origin is this repo on GitHub) in
# Edge, tiled on the right half; then only that tab closes.
slide goto 7 'web page'
beat-pause 4
stage tile-next com.microsoft.edgemac project-tools
press cmd+b
stage wait-tiled
beat-pause 3
stage close-tiled
beat-pause 1.5
```

`beats/07-finale.zsh`:
```zsh
# Beat 7: the cheat sheet; the blog pane closes.
slide goto 8 "That's getting around"
pane close blog
beat-pause 6
```

- [ ] **Step 6: Run the tests** — expected no FAIL lines. (`DEMO_TIMEOUT=30 wait-text …` relies on zsh keeping a prefix assignment for the length of a function call; if the real run still times out at 5 s, report it.)

- [ ] **Step 7: Commit**

```bash
git add kitty/demo/chapters/3-projects kitty/demo/tests/demo-tests.zsh
git commit -m "kitty demo: chapter 3, getting around projects"
```

---

### Task 6: docs

**Files:**
- Modify: `kitty/demo/README.md` (Running, Chapters, verb table, a "Chapter 3 setup" section)
- Modify: `CLAUDE.md` (the `kitty/demo/README.md` bullet's chapter list)

- [ ] **Step 1: README.** Add to "Running": `kitty/demo/play 3                  # chapter 3: getting around projects (its own kitty instance)`. Add a section:

```markdown
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
```

In "Chapters", document `instance` and `build-world`. In the verb table add rows:

```markdown
| `adopt NAME MATCH` | name the one window matching MATCH (`var:demo=stray`, `cmdline:(^\|/)window$`) |
| `wait-gone NAME` / `wait-in-tab NAME TITLE` / `wait-tab TITLE` | readiness after a tool closes or moves windows / switches tab |
| `stage tile-next BUNDLE TITLE` / `stage wait-tiled` / `stage close-tiled` | tile a launcher's app window on the right half, then close it (Edge: only its tab) |
```

- [ ] **Step 2: CLAUDE.md.** In the `kitty/demo/README.md` bullet change `(1 shaders, 2 windows, panes and tabs)` to `(1 shaders, 2 windows, panes and tabs, 3 getting around projects)`.

- [ ] **Step 3: Run the tests** — `zsh kitty/demo/tests/demo-tests.zsh </dev/null | tail -1; echo $?` — expect exit 0.

- [ ] **Step 4: Commit**

```bash
git add kitty/demo/README.md CLAUDE.md
git commit -m "kitty demo: document chapter 3 and its setup"
```

---

### Task 7 (user): rehearsal

- [ ] **Step 1:** Reload Hammerspoon (`hs -c 'hs.reload()'`), since `stage.lua` changed.
- [ ] **Step 2:** `kitty/demo/play 3 --only 0`: a second kitty window opens maximised with five tabs, the deck on the left of tab 1; quitting presenterm (`q`) quits that instance and leaves the user's kitty as it was.
- [ ] **Step 3:** `kitty/demo/play 3` through beat 2: report how many Downs reach the Claude panes' rows in the window switcher, and fix `02-windows.zsh` (and its shape test) to match.
- [ ] **Step 4:** Beat 3 three times: note whether the model closes `docs-log` each time. If it keeps it more than once in three, revisit the staging with the user (the spec's fallback).
- [ ] **Step 5:** Beats 5–6 once with Edge closed and once with an Edge window of your own open: the demo tab closes, your window returns to its frame; abort (Ctrl+Alt+Cmd+.) during beat 6 once and check the same.
- [ ] **Step 6:** Full takes; fix what the user reports, one commit per fix, tests green each time.
