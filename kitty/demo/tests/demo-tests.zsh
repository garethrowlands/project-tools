#!/usr/bin/env zsh
# Tests for kitty/demo: geometry, the verbs (kitty and Hammerspoon stubbed),
# card and play. Needs neither kitty nor Hammerspoon.
#
#   zsh kitty/demo/tests/demo-tests.zsh
#
# Exits 1 if any test fails.

setopt no_bg_nice
DEMO_ROOT=${0:A:h:h}
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
demo_begin $T/play.pid && ok 'demo_begin succeeds' || bad 'demo_begin failed'
is 'demo_begin remembers the layout' "$DEMO_LAYOUT" 'tall'
grep -qx 'goto-layout --match window_id:7 splits' $T/kcalls && ok 'demo_begin switches to splits' || bad 'no splits layout'
is 'demo_begin pins the window'     "$(<$T/hcalls)" "return demoStage.begin(\"$T/play.pid\", 1600, 1000)"
HSREPLY='no focused window' demo_begin $T/play.pid 2>/dev/null && bad 'demo_begin ignored Hammerspoon' || ok 'demo_begin needs Hammerspoon'

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
stage place-beside 'kitty demo W'
is 'stage place-beside' "$(grep placeBeside $T/hcalls)" 'return demoStage.placeBeside("kitty demo W")'
HSREPLY='no window titled kitty demo W' DEMO_TIMEOUT=0.2 stage place-beside 'kitty demo W' 2>/dev/null \
  && bad 'place-beside without the window accepted' || ok 'place-beside waits, then fails'
KGEOM= HSFRAME=

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

zsh $DEMO_ROOT/play --from x >/dev/null 2>&1; is 'bad --from is a usage error' $? 2
zsh $DEMO_ROOT/play --bogus  >/dev/null 2>&1; is 'unknown option is a usage error' $? 2
zsh $DEMO_ROOT/play --dry-run --only 99 >/dev/null 2>&1; is 'no beats selected is a usage error' $? 2

# (later tasks add sections above this line)
exit $fail
