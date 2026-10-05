#!/usr/bin/env zsh
# Tests for kitty/demo: geometry, the verbs (kitty and Hammerspoon stubbed),
# card and play. Needs neither kitty nor Hammerspoon.
#
#   zsh kitty/demo/tests/demo-tests.zsh
#
# Exits 1 if any test fails.

setopt no_bg_nice
zmodload zsh/datetime
DEMO_ROOT=${0:A:h:h}
C1=$DEMO_ROOT/chapters/1-shaders
T=$(mktemp -d)
trap 'rm -rf $T' EXIT
fail=0

ok()  { print -r "PASS $1" }
bad() { print -r "FAIL $1"; fail=1 }
is()  { [[ $2 == "$3" ]] && ok $1 || bad "$1: got ${(q+)2}, want ${(q+)3}" }

source $DEMO_ROOT/geometry.zsh

# --- geometry ---------------------------------------------------------------
# Retina: 2 framebuffer pixels per point. Window 5 fills the left half, 6 the
# right half (40 columns x 50 lines of 40x40 px cells). The frame's title bar
# is 28 points (1028 - 1000).
GEOM='{"os_windows":{"1":{"width":1600,"height":1000,"framebuffer_width":3200,"framebuffer_height":2000}},
       "windows":{"5":{"os_window_id":1,"left":0,"top":0,"right":1600,"bottom":2000,"columns":40,"lines":50},
                  "6":{"os_window_id":1,"left":1600,"top":0,"right":3200,"bottom":2000,"columns":40,"lines":50}}}'
FRAME='{"x":100,"y":50,"w":1600,"h":1028}'

is 'pane centre in points'       "$(demo_point_in_pane $GEOM $FRAME 5 50 50)" '500 578'
is 'pane corner in points'       "$(demo_point_in_pane $GEOM $FRAME 6 0 0)"   '900 78'
is 'cell centre in points'       "$(demo_point_at_cell $GEOM $FRAME 6 2 3)"   '970 128'
demo_point_in_pane $GEOM $FRAME 99 50 50 >/dev/null && bad 'unknown window accepted' || ok 'unknown window rejected'
demo_point_at_cell $GEOM $FRAME 5 x 1 >/dev/null && bad 'bad row accepted' || ok 'bad row rejected'

is 'find text'                   "$(demo_find_text $'ab\nxx TODO: hi\n' 'TODO: hi')" '1 3'
is 'find text after empty rows'  "$(demo_find_text $'\n\nxx a*b' 'a*b')" '2 3'
is 'find text at row start'      "$(demo_find_text $'glitter\nmain.py' 'main.py')" '1 0'
demo_find_text $'a*c\nabc' 'a*b' >/dev/null && bad 'glob chars matched as a pattern' || ok 'glob chars are literal'
demo_find_text $'abc' 'zzz' >/dev/null && bad 'absent text found' || ok 'absent text not found'

# --- verbs (kitty and Hammerspoon stubbed) -----------------------------------
DEMO_STATE=$T/state
source $DEMO_ROOT/lib.zsh

# Stubs. Verbs call these inside $(...), so they keep their state in files.
# kcalls: one line per kitten call; dead: window ids kitty no longer has.
empty_stub_logs() { local f; for f in kcalls hcalls dead; do : >| $T/$f; done }
print 100 >| $T/knext; empty_stub_logs
demo_kitten() {
  print -r -- "$*" >> $T/kcalls
  case $1 in
    launch)
      local n=$(( $(<$T/knext) + 1 )); print $n >| $T/knext
      [[ ${@[-2]} == */card ]] && { mkdir -p $DEMO_STATE; print 1 >| $DEMO_STATE/card-${@[-1]}.pid }
      print $n ;;
    ls)           [[ $2 == --match ]] && grep -qx "${3#id:}" $T/dead && return 1
                  print -r -- ${KLSJSON:-'[]'} ;;
    close-window) ! grep -qx "${3#id:}" $T/dead ;;
    get-text)     print -r -- "$KSCREEN" ;;
    kitten)       [[ -n $KGEOM ]] && print -r -- $KGEOM >| $3 ;;
    *)            return 0 ;;
  esac
}
demo_hs() {
  print -r -- "$1" >> $T/hcalls
  case $1 in
    *demoStage.frame*) print -r -- ${HSFRAME:-'{}'} ;;
    *)                 print -r -- ${HSREPLY:-ok} ;;
  esac
}
demo_sleep() { : }
reset_stubs() {
  print 100 >| $T/knext; empty_stub_logs
  DEMO_IDS=(deck 7); DEMO_CREATED=(); DEMO_DRY=0; DEMO_TIMEOUT=0.2; KSCREEN=''; KLSJSON=''
}

reset_stubs
pane open A --location=vsplit -- card A hello
is 'pane open remembers the id'     "$DEMO_IDS[A] $DEMO_CREATED" '101 101'
is 'pane open launches without focus' "$(grep '^launch' $T/kcalls)" 'launch --keep-focus --title demo A --location=vsplit -- card A hello'
pane ensure A --location=vsplit -- card A hello
is 'pane ensure leaves an open pane alone' "$(grep -c '^launch' $T/kcalls)" 1
pane open B 2>$T/err && bad 'pane open without a command accepted' || ok 'pane open needs a command'
pane close A
is 'pane close forgets it'          "${DEMO_IDS[A]-gone} ${#DEMO_CREATED}" 'gone 0'
is 'pane close closes that window'  "$(grep '^close-window' $T/kcalls)" 'close-window --match id:101'
pane close nosuch && ok 'pane close of an unknown name is a no-op' || bad 'pane close of an unknown name failed'

reset_stubs
print 7 >> $T/dead
pane open A -- card A hi 2>$T/err && bad 'verbs ran without the deck' || ok 'verbs stop when the deck has gone'
[[ $(<$T/err) == *'deck pane has gone'* ]] && ok 'deck-gone message' || bad "deck-gone message: $(<$T/err)"
grep -q '^launch' $T/kcalls && bad 'launched without the deck' || ok 'nothing launched without the deck'

reset_stubs
focus nosuch 2>$T/err && bad 'focus of an unknown pane accepted' || ok 'focus of an unknown pane fails'
DEMO_BEAT=3
focus nosuch 2>$T/err
is 'errors name the beat' "$(<$T/err)" 'beat 3 · no pane named nosuch'
DEMO_BEAT=

reset_stubs
KSCREEN=$'line one\nFocus follows you'
slide goto 2 'Focus follows you' && ok 'slide goto waits for its text' || bad 'slide goto failed'
is 'slide goto types N then G'      "$(grep '^send-text' $T/kcalls)" 'send-text --match id:7 -- 2G'
wait-text deck 'not there' 2>$T/err && bad 'wait-text found absent text' || ok 'wait-text times out'
[[ $(<$T/err) == *"timed out after 0.2s waiting for 'not there' in pane deck"* ]] && ok 'timeout message' || bad "timeout message: $(<$T/err)"
keys focused ctrl+q
is 'keys can target the focused window' "$(grep '^send-key' $T/kcalls)" 'send-key --match state:focused ctrl+q'

reset_stubs
DEMO_DRY=1
is 'dry run prints the verb'        "$(pane open A --location=vsplit -- card A 'two words')" "pane open A --location=vsplit -- card A 'two words'"
lines=(${(f)"$(slide goto 2 $'two\nlines')"})
is 'dry run keeps a multi-line argument on one line' $#lines 1
is 'dry run calls nothing'          "$(<$T/kcalls)" ''

reset_stubs
KLSJSON='[{"tabs":[{"layout":"tall","windows":[{"id":7}]}]}]'
KITTY_PID=99 demo_begin $T/play.pid && ok 'demo_begin succeeds' || bad 'demo_begin failed'
is 'demo_begin remembers the layout' "$DEMO_LAYOUT" 'tall'
grep -qx 'goto-layout --match window_id:7 splits' $T/kcalls && ok 'demo_begin switches to splits' || bad 'no splits layout'
is 'demo_begin pins the window full screen' "$(<$T/hcalls)" "return demoStage.begin(\"$T/play.pid\", 99)"
HSREPLY='no focused window' demo_begin $T/play.pid 2>/dev/null && bad 'demo_begin ignored Hammerspoon' || ok 'demo_begin needs Hammerspoon'
: >| $T/kcalls
DEMO_START_LAYOUT=tall demo_begin $T/play.pid
grep -qx 'goto-layout --match window_id:7 tall' $T/kcalls && ok "demo_begin uses the chapter's layout" || bad 'demo_begin ignored DEMO_START_LAYOUT'
HSREPLY='no focused window' demo_begin $T/play.pid 2>$T/err
[[ $(<$T/err) == *"Hammerspoon could not pin the kitty window: no focused window"* ]] \
  && ok "demo_begin reports Hammerspoon's reply" || bad "demo_begin error: $(<$T/err)"

reset_stubs
DEMO_LAYOUT=tall
pane open A -- card A a; pane open B -- card B b; pane open C -- card C c
print 102 >> $T/dead
: >| $T/kcalls
demo_cleanup && ok 'cleanup succeeds' || bad 'cleanup failed'
is 'cleanup survives a window that has already gone' "$(grep '^close-window' $T/kcalls | awk '{print $3}' | paste -sd' ' -)" 'id:103 id:102 id:101'
is 'cleanup restores the layout'    "$(grep '^goto-layout' $T/kcalls)" 'goto-layout --match window_id:7 tall'
is 'cleanup forgets everything but the deck' "${(kv)DEMO_IDS} ${#DEMO_CREATED}" 'deck 7 0'
grep -q 'demoStage.finish' $T/hcalls && ok 'cleanup restores the frame' || bad 'cleanup did not call finish'

# --- real keys ------------------------------------------------------------------
is 'press args: cmd+shift+enter' "$(demo_press_args cmd+shift+enter)" '{"shift","cmd"}, "return", "⇧⌘↩"'
is 'press args: ctrl+alt+z'      "$(demo_press_args ctrl+alt+z)"      '{"ctrl","alt"}, "z", "⌃⌥Z"'
is 'press args: ctrl+shift+tab'  "$(demo_press_args ctrl+shift+tab)"  '{"ctrl","shift"}, "tab", "⌃⇧⇥"'
is 'press args: cmd+right'       "$(demo_press_args cmd+right)"       '{"cmd"}, "right", "⌘→"'
demo_press_args hyper+x >/dev/null 2>&1 && bad 'unknown modifier accepted' || ok 'unknown modifier rejected'

reset_stubs
press cmd+t
is 'press posts the key with its badge' "$(grep press $T/hcalls)" 'return demoStage.press({"cmd"}, "t", "⌘T")'
HSREPLY='kitty is not the frontmost app' press cmd+t 2>$T/err && bad 'press accepted a refusal' || ok 'press fails when Hammerspoon refuses'
[[ $(<$T/err) == *'⌘T'*'kitty is not the frontmost app'* ]] && ok 'press failure names the key and the reason' || bad "press failure: $(<$T/err)"

# ls JSON helpers: one tab holding the given window ids, the first focused.
# Verbs call demo_hs inside $(...), a subshell, so the fake kitty state lives
# in a file ($T/ls.json) that a stubbed press can rewrite.
lsjson() {
  local -a w; local id f=true
  for id in "$@"; do w+=("{\"id\":$id,\"is_focused\":$f,\"is_active\":$f}"); f=false; done
  print -r -- "[{\"tabs\":[{\"is_active\":true,\"layout\":\"${LAYOUT:-splits}\",\"windows\":[${(j:,:)w}]}]}]"
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

# press-reorders, wait-layout, wait-own-tab
# kitty lists windows in creation order; a move swaps groups (layout order)
grp() { print -r -- "[{\"tabs\":[{\"is_active\":true,\"layout\":\"tall\",\"windows\":[{\"id\":7,\"is_active\":true},{\"id\":5},{\"id\":6}],\"groups\":[$1]}]}]" }
kls "$(grp '{"id":1,"windows":[7]},{"id":2,"windows":[5]},{"id":3,"windows":[6]}')"
AFTER=$(grp '{"id":1,"windows":[7]},{"id":3,"windows":[6]},{"id":2,"windows":[5]}')
press-reorders cmd+shift+right && ok 'press-reorders sees the groups swap' || bad 'press-reorders missed a group swap'
kls "$(LAYOUT=tall lsjson 7 5 6)"
wait-layout tall && ok 'wait-layout sees the layout' || bad 'wait-layout failed'
wait-layout grid 2>/dev/null && bad 'wait-layout accepted the wrong layout' || ok 'wait-layout times out on the wrong layout'
# wait-own-tab: the user's window has other tabs too, so don't count tabs;
# check NAME is alone in a tab without the deck
DEMO_IDS[B]=6
kls '[{"tabs":[{"layout":"grid","windows":[{"id":21}]},{"layout":"tall","windows":[{"id":7},{"id":6}]}]}]'
wait-own-tab B 2>/dev/null && bad 'wait-own-tab accepted B beside the deck' || ok 'wait-own-tab waits while B shares the deck tab'
kls '[{"tabs":[{"layout":"grid","windows":[{"id":21}]},{"layout":"tall","windows":[{"id":7}]},{"layout":"fat","windows":[{"id":6}]}]}]'
wait-own-tab B && ok 'wait-own-tab sees B alone in its own tab, among other tabs' || bad 'wait-own-tab failed'
# kitty marks each tab's active pane is_focused; the one that matters is the
# active pane of the active tab in the deck's OS window
kls '[{"tabs":[{"is_active":true,"layout":"grid","windows":[{"id":21,"is_focused":true,"is_active":true}]}]},
      {"tabs":[{"is_active":false,"layout":"tall","windows":[{"id":184,"is_focused":true,"is_active":true}]},
               {"is_active":true,"layout":"tall","windows":[{"id":7,"is_focused":false,"is_active":false},{"id":262,"is_focused":true,"is_active":true}]}]}]'
is "focus is read from the deck's window and tab" "$(demo_focused_id)" 262
AFTER=''
functions[demo_kitten]=$functions[orig_kitten]
functions[demo_hs]=$functions[orig_hs]

# --- failure snapshot ---------------------------------------------------------------
reset_stubs
KLSJSON='[{"tabs":[{"layout":"stack","windows":[{"id":7,"title":"deck","is_focused":true},{"id":9,"title":"zsh","is_focused":false}]}]}]'
is 'a failure logs each tab layout and its panes' "$(demo_snapshot)" 'kitty: tab layout=stack windows=7*:deck 9:zsh'

# --- card ---------------------------------------------------------------------
source $DEMO_ROOT/card
is 'card centres one line'   "$(card_render 20 5 hi)" $'\e[2J\e[3;10H\e[1mhi\e[22m'
is 'card centres a block'    "$(card_render 10 6 $'ab\ncdef')" $'\e[2J\e[3;5H\e[1mab\e[22m\e[4;4H\e[1mcdef\e[22m'
is 'overlong line starts at column 1' "$(card_render 4 1 abcdefgh)" $'\e[2J\e[1;1H\e[1mabcdefgh\e[22m'

mkdir -p $T/cardstate
DEMO_STATE=$T/cardstate $DEMO_ROOT/card T >$T/card.out 2>&1 </dev/null &
cardpid=$!
for i in {1..30}; do [[ -s $T/cardstate/card-T.pid ]] && break; sleep 0.1; done
is 'card writes its pid' "$(<$T/cardstate/card-T.pid)" $cardpid
print -r -- 'hello there' >| $T/cardstate/card-T.msg
sleep 0.4
[[ $(<$T/card.out) == *'hello there'* ]] && ok 'card shows new text' || bad 'card did not redraw'
kill -USR1 $cardpid; sleep 0.4
[[ $(<$T/card.out) == *$'\a'* ]] && ok 'card rings on USR1' || bad 'card did not ring'
kill -TERM $cardpid; wait $cardpid 2>/dev/null
[[ -e $T/cardstate/card-T.pid ]] && bad 'card left its pid file' || ok 'card removes its pid file'

reset_stubs
card open A 'Ringing in 3…' --location=vsplit && ok 'card open succeeds' || bad 'card open failed'
is 'card open writes the message'   "$(<$DEMO_STATE/card-A.msg)" 'Ringing in 3…'
is 'card open launches card' "$(grep '^launch' $T/kcalls)" "launch --keep-focus --title demo A --location=vsplit -- env DEMO_STATE=$DEMO_STATE $DEMO_ROOT/card A"
card say A 'Ringing in 2…'
is 'card say rewrites the message'  "$(<$DEMO_STATE/card-A.msg)" 'Ringing in 2…'
card say nosuch hi 2>/dev/null && bad 'card say to an unknown pane accepted' || ok 'card say needs an open card'
card ensure A 'other' --location=vsplit
is 'card ensure leaves an open card alone' "$(grep -c '^launch' $T/kcalls)" 1
got_usr1=0; trap 'got_usr1=1' USR1
print $$ >| $DEMO_STATE/card-A.pid
bell A && ok 'bell succeeds' || bad 'bell failed'
is 'bell signals the card' $got_usr1 1
trap - USR1
rm -f $DEMO_STATE/card-A.pid
bell A 2>/dev/null && bad 'bell without a running card accepted' || ok 'bell needs a running card'

# --- mouse and stage ------------------------------------------------------------
reset_stubs
KGEOM=$GEOM HSFRAME=$FRAME
DEMO_IDS[A]=5 DEMO_IDS[B]=6
mouse glide A 50 50 && ok 'mouse glide succeeds' || bad 'mouse glide failed'
is 'mouse glide moves to the pane point' "$(grep glide $T/hcalls)" 'return demoStage.glide(500, 578, 700)'
: >| $T/hcalls
KSCREEN=$'$ rg TODO\n\nxx make it sparkle'
mouse glide-text B 'make it sparkle' 900
is 'mouse glide-text aims at the text' "$(grep glide $T/hcalls)" 'return demoStage.glide(970, 128, 900)'
: >| $T/hcalls
mouse glide-text B 'not on screen' 2>$T/err && bad 'glide-text to absent text accepted' || ok 'glide-text to absent text fails'
[[ $(<$T/err) == *"'not on screen' is not on screen"* ]] && ok 'absent-text message' || bad "absent-text message: $(<$T/err)"
grep -q glide $T/hcalls && bad 'pointer moved towards absent text' || ok 'pointer stays put for absent text'
DEMO_IDS[Z]=99
mouse glide Z 50 50 2>/dev/null && bad 'glide into an unknown window accepted' || ok 'glide into an unknown window fails'
grep -q glide $T/hcalls && bad 'pointer moved for an unknown window' || ok 'pointer stays put for an unknown window'
mouse click cmd
is 'mouse click passes modifiers' "$(grep click $T/hcalls)" 'return demoStage.click({"cmd"})'
: >| $T/hcalls
mouse click
is 'plain mouse click' "$(grep click $T/hcalls)" 'return demoStage.click({})'
KGEOM= HSFRAME=

# --- final-review fixes that need the stubs -------------------------------------------
reset_stubs
stage fill
is 'stage fill gives the main window the whole screen' "$(grep fill $T/hcalls)" 'return demoStage.fill()'
: >| $T/hcalls
stage open-other /x/other-app.txt
stage focus-other other-app.txt
stage focus-main
stage close-other other-app.txt
is 'stage drives another app' "$(<$T/hcalls)" $'return demoStage.openOther("/x/other-app.txt")\nreturn demoStage.otherPlaced()\nreturn demoStage.focusOther("other-app.txt")\nreturn demoStage.focusMain()\nreturn demoStage.closeOther("other-app.txt")'
HSREPLY='not yet' DEMO_TIMEOUT=0.2 stage open-other /x/other-app.txt 2>$T/err \
  && bad 'open-other returned before the window was placed' || ok 'open-other waits for the window to be placed'
HSREPLY='no window titled other-app.txt' stage focus-other other-app.txt 2>/dev/null \
  && bad 'focus-other without its window accepted' || ok 'focus-other needs its window'

# demo_sleep must let a trapped TERM act at once (the abort hotkey), not
# after the whole pause. Run it in a separate zsh with the real lib.zsh.
start=$EPOCHREALTIME
zsh -c "source $DEMO_ROOT/lib.zsh; trap 'exit 3' TERM; demo_sleep 5" &
sleeper=$!
sleep 0.3; kill -TERM $sleeper; wait $sleeper; st=$?
(( EPOCHREALTIME - start < 2 )) && ok 'TERM interrupts demo_sleep' || bad "demo_sleep held TERM for $(( EPOCHREALTIME - start ))s"
is 'TERM during demo_sleep runs the trap' $st 3
zsh -c "source $DEMO_ROOT/lib.zsh; setopt err_return; f() { demo_sleep 0.1; print slept }; f" | grep -q slept \
  && ok 'demo_sleep succeeds under err_return' || bad 'demo_sleep failed under err_return'

# Hammerspoon reads stage.lua only when it loads its config; play must notice
# when the file on disk is newer than the copy it is running.
reset_stubs
zmodload zsh/stat
mtime=$(zstat +mtime $DEMO_ROOT/stage.lua)
HSREPLY=$mtime demo_stage_current && ok 'loaded stage.lua matches the file' || bad 'current stage.lua reported stale'
HSREPLY=$(( mtime - 60 )) demo_stage_current && bad 'stale stage.lua not noticed' || ok 'stale stage.lua is noticed'
HSREPLY=nil demo_stage_current && bad 'stage.lua without a load time accepted' || ok 'stage.lua without a load time is stale'
grep -q 'return demoStage.loadedMtime' $T/hcalls && ok 'asks Hammerspoon for the loaded mtime' || bad 'did not ask for the loaded mtime'

# --- chapter 3 verbs ------------------------------------------------------------------
reset_stubs
KLSJSON='[{"tabs":[{"title":"web-app","is_active":true,"windows":[{"id":7,"is_active":true}]},
                   {"title":"shop-api","is_active":false,"windows":[{"id":21,"is_active":true}]}]}]'
# the stub ignores --match, so give it what kitty would return: the match only
KLSJSON='[{"tabs":[{"title":"scratch","windows":[{"id":21}]}]}]'
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

# cleanup inside the instance closes the deck's OS window, last
reset_stubs; DEMO_INSIDE=1
demo_cleanup
is 'inside cleanup quits the instance last' "$(tail -1 $T/kcalls)" 'action quit'
DEMO_INSIDE=0

# --- review fixes (stubbed) ---
reset_stubs; KLSJSON='[{"tabs":[{"layout":"tall","windows":[{"id":7}]}]}]'
KITTY_PID=4242 demo_begin $T/pidf >/dev/null 2>&1
grep -qF "demoStage.begin(\"$T/pidf\", 4242)" $T/hcalls && ok 'demo_begin pins the kitty with our pid' || bad "begin call: $(grep begin $T/hcalls)"
grep -q 'application():pid()' $DEMO_ROOT/stage.lua && ok 'stage.lua checks kitty by pid' || bad 'stage.lua still tells kitty apart only by bundle id'

# --- play -------------------------------------------------------------------------
# Sourcing play re-sources lib.zsh, which replaces the stubs above with the
# real kitty/Hammerspoon functions; sections from here on run play as a
# dry-run subprocess, and any section needing the stubs goes above this one.
source $DEMO_ROOT/play
mkdir -p $T/beats
for f in 00-a 01-b 10-c; do print "print ran-$f" >| $T/beats/$f.zsh; done
print 'not a beat' >| $T/beats/02-x.txt
is 'all beats, in numeric order' "$(demo_select_beats $T/beats 0 '' | xargs -n1 basename | paste -sd' ' -)" '00-a.zsh 01-b.zsh 10-c.zsh'
is '--from skips earlier beats'  "$(demo_select_beats $T/beats 1 '' | xargs -n1 basename | paste -sd' ' -)" '01-b.zsh 10-c.zsh'
is '--only picks one beat'       "$(demo_select_beats $T/beats 0 10 | xargs -n1 basename)" '10-c.zsh'
is '--only of a missing beat'    "$(demo_select_beats $T/beats 0 5)" ''

print 'print one' >| $T/beats/01-ok.zsh
print 'false\nprint after' >| $T/beats/02-bad.zsh
out=$(demo_run_beats $T/beats/01-ok.zsh $T/beats/02-bad.zsh 2>&1)
st=$?
[[ $out == *one* && $out != *after* && $st != 0 ]] && ok 'a failing verb ends the beat and the run' || bad "run_beats: status $st, output ${(q+)out}"

print $$ >| $T/pid
demo_already_running $T/pid && ok 'a live director is detected' || bad 'live director missed'
print 999999 >| $T/pid
demo_already_running $T/pid && bad 'a dead pid counted as running' || ok 'a dead pid is not running'
print junk >| $T/pid
demo_already_running $T/pid && bad 'junk pid counted as running' || ok 'junk pid is not running'
demo_already_running $T/nosuch && bad 'missing pid file counted as running' || ok 'missing pid file is not running'

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
mkdir -p $T/kconf
print -r -- $'map cmd+t goto_layout tall\nmap\tcmd+left\tneighboring_window left\ninclude extra.conf' >| $T/kconf/kitty.conf
print -r -- 'map cmd+f kitten micro_keys.py cmd+f find -- goto_layout fat' >| $T/kconf/extra.conf
print -r -- $'# needed\ngoto_layout tall\nneighboring_window left\ngoto_layout fat\ngoto_layout grid' >| $T/kconf/requires
is 'mappings in included files count' "$(demo_missing_mappings $T/kconf/requires $T/kconf/kitty.conf)" 'goto_layout grid'
print -r -- 'goto_layout tal' >| $T/kconf/requires2
is 'a mapping must match whole words' "$(demo_missing_mappings $T/kconf/requires2 $T/kconf/kitty.conf)" 'goto_layout tal'

# hs -c mirrors Hammerspoon's console log (e.g. "hotkey: Enabled hotkey")
# before the returned value; demo_hs (the real one, restored by sourcing
# play) must answer with the value alone.
mkdir -p $T/bin
print -r -- $'#!/bin/sh\necho "17:38:33     hotkey: Enabled hotkey x"\necho ok' >| $T/bin/hs
chmod +x $T/bin/hs
is 'demo_hs drops the console log' "$(PATH=$T/bin:$PATH demo_hs 'return 1')" ok
print -r -- $'#!/bin/sh\necho "{\\"x\\":1}"' >| $T/bin/hs
is 'demo_hs keeps a plain reply' "$(PATH=$T/bin:$PATH demo_hs 'return 1')" '{"x":1}'

zsh $DEMO_ROOT/play 1 --from x >/dev/null 2>&1; is 'bad --from is a usage error' $? 2
zsh $DEMO_ROOT/play 1 --bogus  >/dev/null 2>&1; is 'unknown option is a usage error' $? 2
zsh $DEMO_ROOT/play 1 --dry-run --only 99 >/dev/null 2>&1; is 'no beats selected is a usage error' $? 2
for opt in --only --from --slow; do
  # perl's alarm turns a hang into exit 142 instead of hanging the suite
  perl -e 'alarm 3; exec @ARGV' zsh $DEMO_ROOT/play 1 --dry-run $opt >/dev/null 2>&1
  is "$opt without a value is a usage error" $? 2
done

# Quitting presenterm ends the show: play waits for presenterm (no exec,
# since the pane's shell outlives it), then signals the director.
presenterm() { : }
sleep 30 &
director=$!
demo_present $director
sleep 0.2
kill -0 $director 2>/dev/null && { bad 'quitting presenterm left the director running'; kill $director } \
  || ok 'quitting presenterm stops the director'
unfunction presenterm

# --- deck and beats ---------------------------------------------------------------
is 'deck has 16 slides' "$(grep -c '^<!-- end_slide -->' $C1/deck.md)" 15
# Every `slide goto N TEXT` must find TEXT on slide N, or the beat times out.
slides=("${(@ps:<!-- end_slide -->:)$(<$C1/deck.md)}")
for f in $C1/beats/*.zsh; do
  for line in ${(f)"$(grep '^slide goto' $f)"}; do
    words=(${(Q)${(z)line}})
    [[ $slides[$words[3]] == *"$words[4]"* ]] && ok "${f:t:r}: slide $words[3] says '$words[4]'" \
      || bad "${f:t:r}: slide $words[3] doesn't say '$words[4]'"
  done
done
for word in shaders links Hammerspoon live; do
  [[ $slides[1] == *$word* ]] && ok "title slide mentions '$word'" || bad "title slide lacks '$word'"
done
[[ $slides[11] == *'Ctrl+Option+arrow'* ]] && ok 'slide 11 gives the tiling keys' || bad 'slide 11 lacks Ctrl+Option+arrow'
[[ $slides[12] == *'Ctrl+Option+Cmd+arrow'* ]] && ok 'slide 12 gives the focus keys' || bad 'slide 12 lacks Ctrl+Option+Cmd+arrow'
# Beat 8 narrates one state per slide: kitty focused, TextEdit focused, back.
[[ $slides[10] == *amber* ]] && ok 'slide 10: kitty has focus, amber border' || bad 'slide 10 lacks amber'
for word in TextEdit dimmer tint vignette; do
  [[ $slides[11] == *$word* ]] && ok "slide 11 explains '$word'" || bad "slide 11 lacks '$word'"
done
[[ $slides[12] == *pulses* ]] && ok 'slide 12: the border pulses as focus returns' || bad 'slide 12 lacks pulses'
is 'OS-window slides fit a half-width window' "$(print -r -- $slides[10,12] | awk 'length > 48')" ''
[[ $slides[5] == *'subtle trail'* ]] && ok 'cursor slide says the trail is subtle' || bad 'cursor slide lacks "subtle trail"'
for text in 'kitty, with shaders' 'Focus follows you' 'switch tabs' 'and back again' 'cursor go?' 'spotlight' 'Clicks ripple' \
            'pane rang?' 'another tab' 'has focus?' 'Clicking links in the terminal' 'gentle.pipeline'; do
  grep -qF -- $text $C1/deck.md && ok "deck says '$text'" || bad "deck lacks '$text'"
done
dry=$(zsh $DEMO_ROOT/play 1 --dry-run --only 2 2>&1)
is 'beat 2 shows the new tab, switches to it, then back' "$(print -r -- $dry | grep -v '^#' | awk '{print $1, $2}' | paste -sd, -)" \
  'slide goto,beat-pause 1,card open,beat-pause 1.5,focus C,beat-pause 2.5,card say,beat-pause 1.5,slide goto,focus deck,beat-pause 2,pane close,pane close,beat-pause 1'
dry=$(zsh $DEMO_ROOT/play 1 --dry-run --only 1 2>&1)
is 'beat 1 dry-run shape' "$(print -r -- $dry | grep -v '^#' | awk '{print $1, $2}' | paste -sd, -)" \
  'slide goto,beat-pause 1.5,card open,focus A,beat-pause 2,card open,focus B,card say,beat-pause 2,focus deck,card say,card say,beat-pause 2.5'
zsh $DEMO_ROOT/play 1 --dry-run --from 0 >/dev/null 2>&1 && ok 'every beat dry-runs' || bad 'a beat fails its dry run'
is 'comet.txt fits a half-width pane' "$(awk 'length > 60' $C1/scene/comet.txt)" ''
(( $(wc -l < $C1/scene/comet.txt) <= 35 )) && ok 'comet.txt fits a pane without scrolling' || bad 'comet.txt is too long'
[[ $(tail -1 $C1/scene/comet.txt) == *'down at the bottom'* ]] && ok 'comet.txt ends at the bottom line' || bad 'comet.txt last line'

# The ripple and the spotlight only bend or scale existing pixels, so over
# empty background they show nothing: every glide must aim at deck text.
# The one exception is a glide straight after a comment saying it targets
# empty background: beat 5 shows the faint ring the glow gives there.
is 'beat 5 clicks four times' "$(grep -c '^mouse click' $C1/beats/05-ripple.zsh)" 4
is 'beat 5 clicks empty background once' \
  "$(grep -A1 '^#.*empty background' $C1/beats/05-ripple.zsh | grep -c '^mouse glide deck')" 1
for f in 04-spotlight 05-ripple 10-finale; do
  prev=''
  for line in "${(@f)$(<$C1/beats/$f.zsh)}"; do
    if [[ $line == 'mouse glide'* ]]; then
      words=(${(Q)${(z)line}})
      if [[ $prev == '#'*'empty background'* ]]; then
        [[ $words[2] == glide && $words[3] == deck ]] && ok "$f aims at empty background on purpose" \
          || bad "$f: empty-background glide ${(q+)line} isn't a plain deck glide"
      else
        [[ $words[2] == glide-text && $words[3] == deck ]] && grep -qF -- $words[4] $C1/deck.md \
          && ok "$f aims at deck text '$words[4]'" || bad "$f glides to ${(q+)line}, not to deck text"
      fi
    fi
    prev=$line
  done
done

# --- beats 6-10 --------------------------------------------------------------------
dry=$(zsh $DEMO_ROOT/play 1 --dry-run --only 6 2>&1)
is 'beat 6 dry-run shape' "$(print -r -- $dry | grep -v '^#' | awk '{print $1, $2}' | paste -sd, -)" \
  'slide goto,card open,beat-pause 0.6,card say,beat-pause 0.6,card say,beat-pause 0.6,bell A,card say,beat-pause 2.5,pane close'
dry=$(zsh $DEMO_ROOT/play 1 --dry-run --only 7 2>&1)
is '--only 7 opens C itself' "$(print -r -- $dry | grep -v '^#' | sed -n 2p | awk '{print $1, $2, $3}')" 'card open C'
dry=$(zsh $DEMO_ROOT/play 1 --dry-run --only 9 2>&1)
# rg --hyperlink-format=kitty links only the heading and the line number, so
# the click must land on the hit's line number ("5:" at column 0), not its text.
[[ $dry == *"mouse glide-text A '5:# TODO"* && $dry == *'mouse click cmd'* ]] \
  && ok 'beat 9 cmd-clicks the rg hit' || bad 'beat 9 does not cmd-click the rg hit'
[[ $(cd $C1/scene/repo && rg --hyperlink-format=kitty --color=always --heading -n TODO .) \
   == *$'main.py#5\e\\'*5*$'\e]8;;\e\\:#'* ]] && ok 'rg links the line number 5' || bad 'rg no longer links the line number'
dry=$(zsh $DEMO_ROOT/play 1 --dry-run --only 8 2>&1)
is 'beat 8 hands focus to another app and back' \
  "$(print -r -- $dry | grep -E '^(card open|pane|stage)' | awk '{print $1, $2}' | paste -sd, -)" \
  'stage open-other,stage focus-main,stage close-other,stage fill'
is 'beat 8 changes slide before each change of focus' \
  "$(print -r -- $dry | grep -E '^(slide|stage (open|focus))' | awk '{print $1, $2, $3}' | sed 's/ *$//' | paste -sd, -)" \
  'slide goto 10,slide goto 11,stage open-other '"$C1"'/scene/other-app.txt,slide goto 12,stage focus-main'
other=$(grep '^stage open-other' $C1/beats/08-os-window.zsh | awk '{print $3}')
[[ -f ${other/\$DEMO_CHAPTER_DIR/$C1} ]] && ok 'beat 8 opens a scene file' || bad "beat 8 opens a missing file: $other"
for verb in focus-other close-other; do
  for t in ${(f)"$(grep "^stage $verb" $C1/beats/08-os-window.zsh | awk '{print $3}')"}; do
    is "beat 8 $verb names the opened file" ${(Q)t} ${other:t}
  done
done
# Beat 9 narrates one step per slide, each before the step, and proves the cd.
dry=$(zsh $DEMO_ROOT/play 1 --dry-run --only 9 2>&1)
is 'beat 9 changes slide before each step' \
  "$(print -r -- $dry | grep -E '^(slide|mouse glide-text|type-text)' | awk '{ if ($1 == "type-text") print $1, $2; else print $1, $2, $3 }' | paste -sd, -)" \
  'slide goto 13,type-text A,slide goto 14,mouse glide-text A,slide goto 15,mouse glide-text A,type-text A'
[[ $dry == *"type-text A 'pwd; cat sparkle.txt"* ]] && ok 'beat 9 shows where the click took the shell' || bad 'beat 9 does not prove the cd'
is 'link slides fit a half-width window' "$(print -r -- $slides[13,15] | awk 'length > 48')" ''
is 'scene repo has one TODO' "$(rg -c TODO $C1/scene/repo | paste -sd' ' -)" "$C1/scene/repo/main.py:1"
grep -rq glitter $C1/scene/repo/main.py && bad 'glitter appears in rg output' || ok 'glitter only in the eza listing'

# --- chapter 2 -----------------------------------------------------------------------
C2=$DEMO_ROOT/chapters/2-windows
slides2=("${(@ps:<!-- end_slide -->:)$(<$C2/deck.md)}")
is 'chapter 2 has 10 slides' $#slides2 10
is 'chapter 2 slides fit beside three panes' "$(awk 'length > 40' $C2/deck.md)" ''
for f in $C2/beats/*.zsh; do
  for line in ${(f)"$(grep '^slide goto' $f)"}; do
    words=(${(Q)${(z)line}})
    [[ $slides2[$words[3]] == *"$words[4]"* ]] && ok "ch2 ${f:t:r}: slide $words[3] says '$words[4]'" \
      || bad "ch2 ${f:t:r}: slide $words[3] doesn't say '$words[4]'"
  done
done
zsh $DEMO_ROOT/play 2 --dry-run >/dev/null 2>&1 && ok 'chapter 2 dry-runs' || bad 'chapter 2 fails its dry run'
shape() { zsh $DEMO_ROOT/play 2 --dry-run --only $1 2>&1 | grep -E '^(press|wait-layout|wait-own-tab)' | paste -sd, - }
is 'ch2 beat 1 opens A and B with the real key' "$(shape 1)" 'press-new A cmd+shift+enter,press-new B cmd+shift+enter'
[[ $(zsh $DEMO_ROOT/play 2 --dry-run --only 1 2>&1) != *card* ]] && ok 'ch2 beat 1 opens no director panes' || bad 'ch2 beat 1 still opens cards'
is 'ch2 beat 2 hops focus from B, where beat 1 left it' "$(shape 2)" 'press-focus cmd+up,press-focus cmd+left,press-focus cmd+right,press-focus cmd+down'
zsh $DEMO_ROOT/play 2 --dry-run --only 2 2>&1 | grep -q '^focus ' && bad 'ch2 beat 2 moves focus without a key' || ok 'ch2 beat 2 moves focus only with keys'
is 'ch2 beat 3 moves B back and forward' "$(shape 3)" 'press-reorders cmd+shift+left,press-reorders cmd+shift+right'
zsh $DEMO_ROOT/play 2 --dry-run --only 3 2>&1 | grep -q '^focus ' && bad 'ch2 beat 3 moves focus without a key' || ok 'ch2 beat 3 moves focus only with keys'
is 'ch2 beat 3 narrates each move' \
  "$(zsh $DEMO_ROOT/play 2 --dry-run --only 3 2>&1 | grep -E '^(slide|press)' | awk '{print $1, $2, $3}' | sed 's/ *$//' | paste -sd, -)" \
  'slide goto 4,press-reorders cmd+shift+left,slide goto 5,press-reorders cmd+shift+right'
is 'ch2 beat 4 tours the layouts back to tall' "$(shape 4)" 'press cmd+f,wait-layout fat,press cmd+g,wait-layout grid,press cmd+s,wait-layout stack,press cmd+t,wait-layout tall'
is 'ch2 beat 5 zooms and back'             "$(shape 5)" 'press ctrl+alt+z,wait-layout stack,press ctrl+alt+z,wait-layout tall'
is 'ch2 beat 6 detaches a pane'            "$(shape 6)" 'press cmd+shift+up,wait-own-tab B'
is 'ch2 beat 7 returns, then shows its slide, then switches' \
  "$(zsh $DEMO_ROOT/play 2 --dry-run --only 7 2>&1 | grep -E '^(slide|press)' | awk '{print $1, $2}' | paste -sd, -)" \
  'press-focus ctrl+shift+tab,slide goto,press-focus ctrl+tab,press-focus ctrl+shift+tab'
# C splits B (not the slides), so the slides keep half the screen and the
# focus hops have a known neighbour each time
is 'chapter 2 starts in the tall layout' "$(<$C2/layout)" tall
[[ $(zsh $DEMO_ROOT/play 2 --dry-run --only 1 2>&1) != *location* ]] && ok 'chapter 2 lets kitty place its panes' || bad 'chapter 2 still uses split positions'
zsh $DEMO_ROOT/play 2 --dry-run 2>&1 | grep -qE '(^| )C( |$)' && bad 'chapter 2 still uses pane C' || ok 'chapter 2 has no pane C'
# presenterm joins consecutive lines into one paragraph: each cheat-sheet
# entry must be its own list item
body=$(print -r -- $slides2[10] | sed -n '/^=\{3,\}$/,$p' | grep -v '^=*$' | grep -v '^$')
is 'ch2 cheat sheet is one list item per key' "$(print -r -- $body | grep -vc '^\* ')" 0
for req in new_window_with_cwd 'neighboring_window right' move_window_forward move_window_backward 'goto_layout grid' 'toggle_layout stack' 'detach_window new-tab'; do
  grep -qx -- $req $C2/requires && ok "chapter 2 requires $req" || bad "chapter 2 requires lacks $req"
done

# --- stage.lua -----------------------------------------------------------------------
# No Lua outside Hammerspoon here; a stray or missing `end` otherwise only
# shows as a load error in the Hammerspoon console.
out=$(python3 $DEMO_ROOT/tests/lua_blocks.py $DEMO_ROOT/stage.lua) && ok 'stage.lua blocks balance' || bad "$out"
print -r -- $'function f()\n  if x then y() end\nend\nend' >| $T/bad.lua
python3 $DEMO_ROOT/tests/lua_blocks.py $T/bad.lua >/dev/null && bad 'lua_blocks missed a stray end' || ok 'lua_blocks catches a stray end'

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
  [[ -d $W/$p/.git && -z $(git -C $W/$p status --porcelain) ]] && ok "$p is clean" || bad "$p is dirty"
  is "$p has nothing unpushed" "$(git -C $W/$p rev-list --count @{u}..HEAD)" 0
done
is 'blog points at the real repo' "$(git -C $W/blog remote get-url origin)" https://github.com/garethrowlands/project-tools.git
is 'shop-api points at a fake host' "$(git -C $W/shop-api remote get-url origin)" git@example.com:demo/shop-api.git
(( $(git -C $W/docs log -1 --format=%ct) < EPOCHSECONDS - 30 * 86400 )) && ok 'docs looks stale' || bad 'docs commits are recent'
(( $(git -C $W/shop-api log -1 --format=%ct) > EPOCHSECONDS - 86400 )) && ok 'shop-api looks fresh' || bad 'shop-api commits are old'
is 'zoxide ranks the projects' "$(_ZO_DATA_DIR=$S/zoxide zoxide query --list | sed 's:.*/::' | paste -sd' ' -)" 'shop-api web-app infra docs blog'
[[ ! -e $S/projects.txt ]] && ok 'project cache is cleared' || bad 'project cache left behind'
grep -qx "launch --hold --var demo=deck 'echo' 'the deck'" $S/session.kitty && ok 'deck window runs the deck command, and holds' || bad "deck line: $(grep demo=deck $S/session.kitty)"
grep -q 'demo=web-shell' $S/session.kitty && bad 'the slides share their tab with a shell' || ok 'the slides have their tab to themselves'
grep -qx 'launch --var demo=shop-claude claude --resume sid-shop' $S/session.kitty && ok 'shop-api tab resumes its session' || bad 'no shop-api claude line'
grep -qx 'launch --var demo=infra-claude claude --resume sid-infra' $S/session.kitty && ok 'infra tab resumes its session' || bad 'no infra claude line'
is 'session tabs' "$(sed -n 's/^new_tab //p' $S/session.kitty | paste -sd' ' -)" 'web-app shop-api infra docs scratch'
grep -qx 'focus_tab 0' $S/session.kitty && ok 'session starts on the deck tab' || bad 'session does not focus tab 0'
is 'stray shell sits in shop-api' "$(grep -B1 'demo=stray' $S/session.kitty | head -1)" "cd $W/shop-api"
print -r -- '{"keep":1,"projects":{"/elsewhere":{"hasTrustDialogAccepted":false}}}' >| $CD/.claude.json
bw $W $S -- echo 'the deck' >/dev/null 2>&1
is 'shop-api folder is trusted' "$(jq -r --arg p $W/shop-api '.projects[$p].hasTrustDialogAccepted' $CD/.claude.json)" true
is 'infra folder is trusted' "$(jq -r --arg p $W/infra '.projects[$p].hasTrustDialogAccepted' $CD/.claude.json)" true
is 'the rest of .claude.json is kept' "$(jq -c '[.keep, .projects["/elsewhere"].hasTrustDialogAccepted]' $CD/.claude.json)" '[1,false]'
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

mkdir -p $T/bin3 $T/cd3
print -r -- '#!/bin/zsh
print -r -- "{\"session_id\":\"sid-${PWD:t}\",\"result\":\"ok\"}"' >| $T/bin3/claude
chmod +x $T/bin3/claude
PATH=$T/bin3:$PATH CLAUDE_DEMO_DIR=$T/cd3 DEMO_WORLD=$T/w7 TMPDIR=$T/tmp3 \
  zsh -f $C3/setup-claude >/dev/null 2>$T/sc.err; is 'setup-claude succeeds' $? 0
is 'setup-claude records both sessions' "$(<$T/cd3/kitty-demo-sessions)" $'shop-api sid-shop-api\ninfra sid-infra'
CLAUDE_DEMO_DIR=$T/absent zsh $C3/setup-claude >/dev/null 2>$T/sc.err
[[ $? == 1 && $(<$T/sc.err) == *'claude'* ]] && ok 'setup-claude asks for a login first' || bad "setup-claude without profile: $(<$T/sc.err)"

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
# pre-flight for an instance chapter
demo_hs() { print -r -- false }   # no Hammerspoon here
out=$(CLAUDE_DEMO_DIR=$T/none DEMO_WORLD=$T/mine DEMO_CHAPTER_DIR=$C3 demo_preflight_instance 2>&1)
[[ $out == *setup-claude* ]] && ok 'pre-flight points at setup-claude' || bad "pre-flight: $out"
[[ $out == *DEMO_WORLD* ]] && ok 'pre-flight refuses an unmarked world' || bad "pre-flight: $out"
zsh $DEMO_ROOT/play 1 --inside --dry-run >/dev/null 2>&1; is '--inside is accepted' $? 0

# --- chapter 3 -----------------------------------------------------------------------
slides3=("${(@ps:<!-- end_slide -->:)$(<$C3/deck.md)}")
is 'chapter 3 has 10 slides' $#slides3 10
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
is 'ch3 beat 0 tours the tabs and wraps back to the slides' "$(shape3 0)" \
  'press ctrl+tab,wait-tab shop-api,press ctrl+tab,wait-tab infra,press ctrl+tab,wait-tab docs,press ctrl+tab,wait-tab scratch,press ctrl+tab,wait-tab web-app'
is 'ch3 intro explains before the tour and maps the keys after' \
  "$(zsh $DEMO_ROOT/play 3 --dry-run --only 0 2>&1 | grep -E '^(slide|press)' | awk '{print $1, $2, $3}' | sed 's/ *$//' | uniq | paste -sd, -)" \
  'slide goto 1,slide goto 2,press ctrl+tab,slide goto 3'
is 'ch3 beat 1 jumps to shop-api and back' "$(shape3 1)" \
  'press cmd+§,adopt picker,wait-text picker,type-text picker,press enter,wait-tab shop-api,press ctrl+shift+tab,wait-tab web-app'
is 'ch3 beat 2 browses the switcher and leaves' "$(shape3 2)" \
  'press alt+tab,adopt switcher,wait-text switcher,type-text switcher,wait-text switcher,press escape,wait-gone switcher'
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
body=$(print -r -- $slides3[10] | sed -n '/^=\{3,\}$/,$p' | grep -v '^=*$' | grep -v '^$')
is 'ch3 cheat sheet is one list item per key' "$(print -r -- $body | grep -vc '^\* ')" 0

# --- review fixes ---
# kitty's match parser reads ( ) as grouping: a regex with brackets must be quoted
is 'ch3 adopt regexes are quoted for kitty' "$(grep -hE "^adopt [a-z-]+ '[a-z_]+:[(]" $C3/beats/*.zsh)" ''
demo_edge_urls() { print -r -- $'https://example.com/\nhttps://github.com/garethrowlands/project-tools/pull/3' }
demo_hs() { [[ $1 == *"application.get('com.microsoft.VSCode')"* ]] && print true || print false }
out=$(CLAUDE_DEMO_DIR=$T/none DEMO_WORLD=$T/mine DEMO_CHAPTER_DIR=$C3 demo_preflight_instance 2>&1)
[[ $out == *'Quit VS Code'* ]] && ok 'pre-flight refuses a running VS Code' || bad "pre-flight with VS Code: $out"
[[ $out == *'an Edge tab is open on github.com/garethrowlands/project-tools'* ]] && ok 'pre-flight refuses an open project-tools tab in Edge' || bad "pre-flight with Edge tab: $out"

# the stub accepts any kitten @ command: check every one the demo uses exists
# in kitty 0.49 (there is no close-os-window, for instance)
rc=(action close-tab close-window create-marker detach-tab detach-window disable-ligatures env focus-tab
    focus-window get-colors get-text goto-layout kitten last-used-layout launch load-config ls new-window
    remove-marker resize-os-window resize-window run screenshot scroll-window select-window send-key
    send-text set-background-image set-background-opacity set-colors set-enabled-layouts set-font-size
    set-os-window-title set-spacing set-tab-color set-tab-title set-user-vars set-window-logo
    set-window-title signal-child)
used=(${(u)${(f)"$(grep -ohE 'demo_kitten [a-z-]+' $DEMO_ROOT/*.zsh $DEMO_ROOT/play $DEMO_ROOT/chapters/*/beats/*.zsh | awk '{print $2}')"}})
missing=(${used:|rc})
is 'every kitten @ command the demo uses exists' "$missing" ''

# (later tasks add sections above this line)
exit $fail
