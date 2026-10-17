# Verbs the kitty demo's beats are written in (see README.md), plus the run's
# state and cleanup. Sourced by play and by tests/demo-tests.zsh.
#
# A verb that can't do its job prints "beat N · <what>" on stderr and returns
# non-zero; play sources each beat with ERR_RETURN, so the first failure ends
# the run and play's EXIT trap calls demo_cleanup.
# With DEMO_DRY=1 every verb prints itself instead (play --dry-run).

typeset -g DEMO_ROOT=${DEMO_ROOT:-${${(%):-%x}:A:h}}
source $DEMO_ROOT/geometry.zsh

typeset -gA DEMO_IDS          # pane name -> kitty window id, "deck" included
typeset -ga DEMO_CREATED      # ids of windows the demo opened, oldest first
typeset -g  DEMO_DRY=${DEMO_DRY:-0} DEMO_SLOW=${DEMO_SLOW:-1} DEMO_BEAT=${DEMO_BEAT:-}
typeset -g  DEMO_STATE=${DEMO_STATE:-${TMPDIR:-/tmp}/kitty-demo}
typeset -g  DEMO_TIMEOUT=${DEMO_TIMEOUT:-5}   # seconds a readiness poll may take
typeset -g  DEMO_LAYOUT=''                    # the deck tab's layout before the run
typeset -g  DEMO_RECORD=${DEMO_RECORD:-}     # play --record FILE: the video to write
typeset -g  DEMO_QUIT_DECK=                   # set once a --record take has run clean: quit the deck after cleanup
typeset -g  DEMO_INSIDE=${DEMO_INSIDE:-0}     # 1: running in a chapter's own kitty instance

# The outside world, as functions the tests replace.
demo_kitten() { command kitten @ "$@" }
# hs -c mirrors Hammerspoon's console log (e.g. "hotkey: Enabled hotkey …")
# ahead of the returned value, which is always the last line.
demo_hs() {
  local out
  out=$(command hs -c "$1") || return
  local -a lines=("${(@f)out}")
  print -r -- $lines[-1]
}
# zsh runs a trap only once a foreground command finishes, so a plain sleep
# would hold the abort hotkey's TERM for the whole pause. The wait builtin
# returns as soon as a trapped signal arrives.
demo_sleep() {
  setopt local_options no_bg_nice
  command sleep $1 &
  local pid=$!
  wait $pid || :
  kill $pid 2>/dev/null || :
  return 0
}

demo_err() { print -ru2 -- "beat ${DEMO_BEAT:-?} · $*"; return 1 }

# In a dry run print the command, shell-quoted, on one line, and succeed;
# otherwise fail so the caller goes on to do the real thing. Words with
# control characters (newlines) get $'...' quoting, the rest only the quotes
# they need, so --location=vsplit stays readable.
demo_dry() {
  (( DEMO_DRY )) || return 1
  local -a words
  local w
  for w in "$@"; do
    if [[ $w == *[[:cntrl:]]* ]]; then words+=(${(q+)w}); else words+=(${(q-)w}); fi
  done
  print -r -- "${(j: :)words}"
}

demo_id() {
  [[ -n ${DEMO_IDS[$1]} ]] || { demo_err "no pane named $1"; return 1 }
  print -r -- ${DEMO_IDS[$1]}
}

# kitty --match for a pane name; "focused" is whichever window has focus.
demo_match() {
  if [[ $1 == focused ]]; then
    print -r -- state:focused
  else
    local id; id=$(demo_id $1) || return
    print -r -- id:$id
  fi
}

demo_lua_str() {
  local s=${1//\\/\\\\}
  print -r -- "\"${s//\"/\\\"}\""
}

# demo_poll WHAT CMD...: run CMD every 0.1 s until it succeeds, for at most
# DEMO_TIMEOUT seconds of real time (not a count of tries: a check that is
# slow to fail, like a call to a hung Hammerspoon, mustn't stretch it). For
# readiness only; pacing is beat-pause.
demo_poll() {
  zmodload -F zsh/datetime p:EPOCHREALTIME
  local what=$1; shift
  local deadline=$(( EPOCHREALTIME + DEMO_TIMEOUT ))
  while :; do
    "$@" && return 0
    (( EPOCHREALTIME < deadline )) || break
    demo_sleep 0.1
  done
  demo_err "timed out after ${DEMO_TIMEOUT}s waiting for $what"
}

demo_window_exists() { demo_kitten ls --match id:$1 >/dev/null 2>&1 }
demo_kitten_match()  { demo_kitten ls --match "$1" >/dev/null 2>&1 }
demo_has_text()      { [[ $(demo_kitten get-text --match id:$1 2>/dev/null) == *"$2"* ]] }

# Quitting presenterm is how a viewer stops the show, so every verb that
# touches kitty checks the deck first.
demo_deck_alive() {
  demo_window_exists ${DEMO_IDS[deck]} || demo_err "the deck pane has gone; stopping"
}

# pane open NAME [LAUNCH-OPTION...] -- CMD...
#   Open a kitty window running CMD without taking focus (beats focus
#   explicitly), remember it as NAME and wait until kitty lists it.
#   LAUNCH-OPTIONs go to `kitten @ launch`: --location=vsplit|hsplit,
#   --type=tab, --type=os-window --os-window-title=T, --cwd=DIR.
# pane ensure NAME ... -- CMD...   open unless NAME is open (for --from/--only)
# pane close NAME                  close it; nothing to do if it isn't open
pane() {
  local sub=$1 name=$2; shift 2
  case $sub in
    ensure)
      [[ -n ${DEMO_IDS[$name]} ]] && return 0
      pane open $name "$@" ;;
    open)
      demo_dry pane open $name "$@" && { DEMO_IDS[$name]=dry-$name; return 0 }
      local -a opts
      while (( $# )) && [[ $1 != -- ]]; do opts+=($1); shift; done
      (( $# )) && shift
      (( $# )) || { demo_err "pane open $name: no command"; return 1 }
      demo_deck_alive || return
      local id
      id=$(demo_kitten launch --keep-focus --title "demo $name" $opts -- "$@") && [[ $id == <-> ]] \
        || { demo_err "pane open $name: kitty would not launch it"; return 1 }
      DEMO_IDS[$name]=$id
      DEMO_CREATED+=($id)
      demo_poll "pane $name to appear" demo_window_exists $id ;;
    close)
      demo_dry pane close $name && { unset "DEMO_IDS[$name]"; return 0 }
      local id=${DEMO_IDS[$name]}
      [[ -n $id ]] || return 0
      unset "DEMO_IDS[$name]"
      DEMO_CREATED=(${DEMO_CREATED:#$id})
      demo_kitten close-window --match id:$id >/dev/null 2>&1 \
        || demo_err "pane close $name: kitty could not close window $id" ;;
    *)
      demo_err "pane: unknown subcommand $sub" ;;
  esac
}

# focus NAME: keyboard focus to NAME, switching tab or OS window if need be.
focus() {
  demo_dry focus "$@" && return 0
  local id; id=$(demo_id $1) || return
  demo_deck_alive || return
  demo_kitten focus-window --match id:$id >/dev/null || demo_err "focus $1 failed"
}

# keys NAME KEY...: key presses (kitty names: end, ctrl+end, ctrl+f) straight
# to NAME's program, bypassing kitty's own shortcuts.
keys() {
  demo_dry keys "$@" && return 0
  local match; match=$(demo_match $1) || return
  shift
  demo_deck_alive || return
  demo_kitten send-key --match $match "$@" >/dev/null || demo_err "keys $*: send-key failed"
}

# type-text NAME TEXT: TEXT to NAME's program as if typed. kitty interprets
# escapes in it, so a literal \r (in single quotes) is Enter.
type-text() {
  demo_dry type-text "$@" && return 0
  local match; match=$(demo_match $1) || return
  demo_deck_alive || return
  demo_kitten send-text --match $match -- "$2" >/dev/null || demo_err "type-text $1 failed"
}

# wait-text NAME TEXT: wait until TEXT is on NAME's screen.
wait-text() {
  demo_dry wait-text "$@" && return 0
  local id; id=$(demo_id $1) || return
  demo_poll "'$2' in pane $1" demo_has_text $id "$2"
}

# wait-window MATCH: wait until a kitty window matches MATCH (kitty match
# syntax, e.g. "state:focused and cmdline:micro").
wait-window() {
  demo_dry wait-window "$@" && return 0
  demo_poll "a window matching $1" demo_kitten_match "$1"
}

# slide goto N TEXT: show deck slide N (1-based; presenterm's "<N>G") and
# wait until TEXT is on screen.
slide() {
  [[ $1 == goto ]] || { demo_err "slide: unknown subcommand $1"; return 1 }
  demo_dry slide "$@" && return 0
  type-text deck "${2}G" && wait-text deck "$3"
}

# reveal TEXT [SECONDS]: bring up the deck slide's next list item (the deck
# uses presenterm's incremental lists) until TEXT shows, then hold for
# SECONDS (default 3) so it can be read. presenterm may pause once more
# before or after a list, so it presses "next" up to three times; an item
# already on screen needs no press.
reveal() {
  demo_dry reveal "$@" && return 0
  local id i j; id=$(demo_id deck) || return
  demo_has_text $id "$1" && { beat-pause ${2:-3}; return }
  for (( i = 0; i < 3; i++ )); do
    keys deck right || return
    for (( j = 0; j < 10; j++ )); do
      demo_has_text $id "$1" && { beat-pause ${2:-3}; return }
      demo_sleep 0.1
    done
  done
  demo_err "reveal: '$1' never showed on the deck"
}

# beat-pause SECONDS: pacing, scaled by play --slow.
beat-pause() {
  demo_dry beat-pause "$@" && return 0
  demo_sleep $(( $1 * DEMO_SLOW ))
}

# True if Hammerspoon is running the current stage.lua: it reads the file
# only when it loads its config, so after an edit it needs a reload.
demo_stage_current() {
  zmodload -F zsh/stat b:zstat
  local loaded on_disk
  loaded=$(demo_hs 'return demoStage.loadedMtime')
  on_disk=$(zstat +mtime $DEMO_ROOT/stage.lua) || return 1
  [[ $loaded == <-> ]] && (( loaded >= on_disk ))
}

# Start of a real run: the deck's tab goes to the chapter's layout
# (DEMO_START_LAYOUT, from its `layout` file; default splits, for vsplit/hsplit) and Hammerspoon pins the focused kitty OS window, makes it
# fill the screen, parks the pointer near its top right and arms the abort hotkey, which
# signals the pid in PIDFILE.
demo_begin() {
  local deck=${DEMO_IDS[deck]} pidfile=$1
  DEMO_LAYOUT=$(demo_kitten ls --match id:$deck \
    | jq -r ".[].tabs[] | select(any(.windows[]; .id == $deck)) | .layout") \
    && [[ -n $DEMO_LAYOUT ]] || { demo_err "cannot read the deck tab's layout"; return 1 }
  local layout=${DEMO_START_LAYOUT:-splits}
  demo_kitten goto-layout --match window_id:$deck $layout >/dev/null \
    || { demo_err "cannot switch to the $layout layout (is it in enabled_layouts?)"; return 1 }
  # Pin this kitty by its pid: a second kitty (chapter 3's own instance)
  # shares the user's bundle id, and may take a moment to become key.
  demo_poll "Hammerspoon to pin this kitty's window" demo_pin $pidfile \
    || { demo_err "Hammerspoon could not pin the kitty window: ${DEMO_PIN_REPLY:-no reply}"; return 1 }
}
demo_pin() {
  DEMO_PIN_REPLY=$(demo_hs "return demoStage.begin($(demo_lua_str $1), ${KITTY_PID:-nil})" 2>&1)
  [[ $DEMO_PIN_REPLY == ok ]]
}

# demo_record_start: with play --record, start recording the pinned kitty
# window's display. Hammerspoon runs screencapture, so it can stop it with
# SIGINT, which is how screencapture finishes its file (a background job of
# this script would ignore SIGINT). It records the display kitty is on;
# DEMO_RECORD_DISPLAY=N picks screencapture's display N instead (1 = main).
# Nothing to do without --record.
demo_record_start() {
  [[ -n $DEMO_RECORD ]] || return 0
  local reply
  reply=$(demo_hs "return demoStage.recordStart($(demo_lua_str $DEMO_RECORD)${DEMO_RECORD_DISPLAY:+, $DEMO_RECORD_DISPLAY})")
  [[ $reply == ok ]] || { demo_err "cannot record: ${reply:-no reply}"; return 1 }
  demo_sleep 1
  demo_recording || { demo_err "screencapture stopped at once: give Hammerspoon Screen Recording permission (System Settings › Privacy & Security)"; return 1 }
}

# demo_record_stop: stop recording and wait until the file is written.
demo_record_stop() {
  [[ -n $DEMO_RECORD ]] || return 0
  demo_hs 'return demoStage.recordStop()' >/dev/null
  local DEMO_TIMEOUT=${DEMO_TIMEOUT_RECORD:-15}
  demo_poll "screencapture to finish writing $DEMO_RECORD" demo_not_recording
}
demo_recording()     { [[ $(demo_hs 'return demoStage.recordRunning()') == yes ]] }
demo_not_recording() { ! demo_recording }

# Close every window the demo opened, newest first (ones already gone are
# fine), then restore the deck tab's layout and the window frame. Runs from
# play's EXIT trap, so it always succeeds.
demo_cleanup() {
  local id deck=${DEMO_IDS[deck]}
  # first, so the video ends on the last slide, not on the teardown
  demo_record_stop >/dev/null 2>&1
  for id in ${(Oa)DEMO_CREATED}; do
    demo_kitten close-window --match id:$id >/dev/null 2>&1
  done
  DEMO_CREATED=()
  DEMO_IDS=(deck "$deck")
  if [[ -n $DEMO_LAYOUT ]]; then
    demo_kitten goto-layout --match window_id:$deck $DEMO_LAYOUT >/dev/null 2>&1
  fi
  demo_hs 'return demoStage.finish()' >/dev/null 2>&1
  # A take that ran clean quits its deck (presenterm) itself, so a chain of
  # takes carries on without anyone pressing q. After the recording stopped
  # and everything was put back; never on an abort or a failure, where the
  # deck stays up to look at. (An instance's quit, below, takes the deck too.)
  if [[ -n $DEMO_QUIT_DECK ]]; then
    print -r -- '# take finished: quitting the deck'
    demo_kitten send-key --match id:$deck q >/dev/null 2>&1 || print -r -- '# sending q to the deck failed'
  fi
  # In a chapter's own kitty instance, quit that instance (it runs with
  # confirm_os_window_close=0, so kitty doesn't ask; kitten @ has no command
  # to close an OS window). It ends this process too, so it comes last.
  (( DEMO_INSIDE )) && demo_kitten action quit >/dev/null 2>&1
  return 0
}

# card open NAME TEXT [LAUNCH-OPTION...]   a pane running ./card, showing TEXT
# card ensure NAME TEXT [LAUNCH-OPTION...] open unless NAME is open
# card say NAME TEXT                       change what it shows
card() {
  local sub=$1 name=$2 text=$3; shift 3
  case $sub in
    ensure)
      [[ -n ${DEMO_IDS[$name]} ]] && return 0
      card open $name $text "$@" ;;
    open)
      demo_dry card open $name $text "$@" && { DEMO_IDS[$name]=dry-$name; return 0 }
      demo_card_write $name $text || return
      rm -f $DEMO_STATE/card-$name.pid
      pane open $name "$@" -- env DEMO_STATE=$DEMO_STATE $DEMO_ROOT/card $name || return
      demo_poll "card $name to start" test -s $DEMO_STATE/card-$name.pid ;;
    say)
      demo_dry card say $name $text && return 0
      demo_id $name >/dev/null || return
      demo_card_write $name $text ;;
    *)
      demo_err "card: unknown subcommand $sub" ;;
  esac
}

demo_card_write() {
  mkdir -p $DEMO_STATE \
    && print -r -- $2 >| $DEMO_STATE/card-$1.msg.tmp \
    && mv -f $DEMO_STATE/card-$1.msg.tmp $DEMO_STATE/card-$1.msg \
    || demo_err "card $1: cannot write its message"
}

# bell NAME: NAME's card rings the terminal bell, so the bell comes from the
# pane's own program (kitty then fires bell-in-window for that pane).
bell() {
  demo_dry bell "$@" && return 0
  demo_id $1 >/dev/null || return
  local pid; pid=$(<$DEMO_STATE/card-$1.pid 2>/dev/null)
  [[ $pid == <-> ]] && kill -USR1 $pid 2>/dev/null || demo_err "bell $1: its card isn't running"
}

# mouse glide NAME XPCT YPCT [MS]   ease the pointer to a point in NAME (0..100)
# mouse glide-text NAME TEXT [MS]   ...to the first character of TEXT on NAME's screen
# mouse click [cmd]                 left click where the pointer is
# The pointer moves with real events, so kitty's spotlight and ripple react.
# NAME must be a pane in the main OS window (the one demo_begin pinned).
mouse() {
  demo_dry mouse "$@" && return 0
  local sub=$1; shift
  demo_deck_alive || return
  local id point pos
  case $sub in
    glide)
      id=$(demo_id $1) || return
      point=$(demo_screen_point $id pane $2 $3) || return
      demo_glide ${=point} ${4:-700} ;;
    glide-text)
      id=$(demo_id $1) || return
      pos=$(demo_find_text "$(demo_kitten get-text --match id:$id)" "$2") \
        || { demo_err "mouse glide-text $1: '$2' is not on screen"; return 1 }
      point=$(demo_screen_point $id cell ${=pos}) || return
      demo_glide ${=point} ${3:-700} ;;
    click)
      local mods='{}'
      [[ -n $1 ]] && mods="{\"$1\"}"
      [[ $(demo_hs "return demoStage.click($mods)") == ok ]] || { demo_err "mouse click failed"; return 1 }
      demo_sleep 0.1 ;;
    *)
      demo_err "mouse: unknown subcommand $sub" ;;
  esac
}

# demo_screen_point ID pane XPCT YPCT | ID cell ROW COL -> "x y" in screen points
demo_screen_point() {
  local id=$1 kind=$2 geom frame point
  geom=$(demo_geometry) || return
  frame=$(demo_hs 'return demoStage.frame()') && [[ $frame == \{* ]] \
    || { demo_err "Hammerspoon has no frame for the kitty window"; return 1 }
  if [[ $kind == pane ]]; then
    point=$(demo_point_in_pane $geom $frame $id $3 $4)
  else
    point=$(demo_point_at_cell $geom $frame $id $3 $4)
  fi
  [[ -n $point ]] || { demo_err "no geometry for window $id"; return 1 }
  print -r -- $point
}

# Every window's pixel rectangle, from the geometry kitten inside kitty.
demo_geometry() {
  local out=$DEMO_STATE/geometry.json
  mkdir -p $DEMO_STATE && rm -f $out
  demo_kitten kitten $DEMO_ROOT/demo_geometry.py $out >/dev/null 2>&1 \
    || { demo_err "the geometry kitten failed to run"; return 1 }
  demo_poll "the geometry kitten's output" test -s $out || return
  print -r -- "$(<$out)"
}

# demo_glide X Y MS: start the glide and wait for it to finish.
demo_glide() {
  [[ $(demo_hs "return demoStage.glide($1, $2, $3)") == ok ]] || { demo_err "mouse glide failed"; return 1 }
  demo_sleep $(( $3 / 1000.0 + 0.05 ))
}

demo_tiled_placed() { [[ $(demo_hs 'return demoStage.tiledPlaced()') == ok ]] }
demo_other_placed() { [[ $(demo_hs 'return demoStage.otherPlaced()') == ok ]] }
demo_stack_placed() { [[ $(demo_hs 'return demoStage.stackPlaced()') == ok ]] }

# stage open-other FILE: make room (the main window takes the left half of
#   the screen), open FILE in another app (TextEdit) and wait until
#   Hammerspoon has put its window on the right half and given it focus.
# stage focus-other TITLE / stage focus-main: move focus between that app's
#   window and kitty.
# stage close-other TITLE: close that window (and TextEdit, if the demo
#   started it).
# stage open-stack FILE...: the same, for several files: their windows pile
#   up on the right half (the last on top, focused). Waits until all are there.
# stage close-stack: close them (and TextEdit, if the demo started it).
# stage press-other KEYS: like press, for keys Hammerspoon acts on, with
#   that app frontmost (kitty isn't, after open-other / open-stack).
# stage fill: give the main window the whole screen again.
# stage tile-next BUNDLE TITLE: before a launcher key, arm Hammerspoon to
#   tile the app's window (title containing TITLE) on the right half.
# stage wait-tiled: wait (up to 30 s: an IDE starts slowly) until it has.
# stage close-tiled: close that window or tab and give kitty the screen.
stage() {
  demo_dry stage "$@" && return 0
  local call
  case $1 in
    fill)        call='demoStage.fill()' ;;
    open-other)  call="demoStage.openOther($(demo_lua_str $2))" ;;
    focus-other) call="demoStage.focusOther($(demo_lua_str $2))" ;;
    focus-main)  call='demoStage.focusMain()' ;;
    close-other) call="demoStage.closeOther($(demo_lua_str $2))" ;;
    open-stack)  local -a quoted; local f
                 for f in ${@:2}; do quoted+=("$(demo_lua_str $f)"); done
                 call="demoStage.openStack({${(j:, :)quoted}})" ;;
    close-stack) call='demoStage.closeStack()' ;;
    press-other) local args; args=$(demo_press_args $2) || { demo_err "stage press-other $2: bad keys"; return 1 }
                 call="demoStage.pressOther($args)" ;;
    tile-next)   call="demoStage.tileNext($(demo_lua_str $2), $(demo_lua_str $3))" ;;
    wait-tiled)  # an IDE can take a while to start; tests shorten it
                 local DEMO_TIMEOUT=${DEMO_TIMEOUT_TILED:-30}
                 demo_poll "the app's window to be tiled" demo_tiled_placed; return ;;
    close-tiled) call='demoStage.closeTiled()' ;;
    *) demo_err "stage: unknown subcommand $1"; return 1 ;;
  esac
  local reply
  reply=$(demo_hs "return $call")
  [[ $reply == ok ]] || { demo_err "stage $*: ${reply:-no reply}"; return 1 }
  if [[ $1 == open-other ]]; then
    demo_poll "the other app's window to be placed" demo_other_placed
  fi
  if [[ $1 == open-stack ]]; then
    demo_poll "the stacked windows to be placed" demo_stack_placed
  fi
}

# demo_press_args KEYS: Lua arguments for demoStage.press from KEYS such as
# cmd+shift+enter: the modifiers, Hammerspoon's key name and the badge
# label, modifiers in Mac order (⌃⌥⇧⌘).
demo_press_args() {
  local -a parts=(${(s:+:)1}) mods
  local key=$parts[-1] m label=''
  local -A glyph=(ctrl ⌃ alt ⌥ shift ⇧ cmd ⌘)
  local -A hsname=(enter return)
  local -A keyglyph=(left ← right → up ↑ down ↓ enter ↩ return ↩ tab ⇥ escape ⎋)
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
  local reply; reply=$(demo_hs "return demoStage.press($args)")
  [[ $reply == ok ]] || { demo_err "press $(demo_badge $1): ${reply:-no reply}"; return 1 }
}

demo_badge() { demo_press_args $1 | sed 's/.*, "\(.*\)"$/\1/' }

demo_ls_ids()     { demo_kitten ls | jq -r '[.[].tabs[].windows[].id] | sort | .[]' }
# The focused pane: the active pane of the active tab in the deck's OS window
# (kitty marks every tab's active pane is_focused, so that alone is not enough).
demo_focused_id() {
  demo_kitten ls | jq -r --argjson d ${DEMO_IDS[deck]:-0} '[.[] | select(any(.tabs[].windows[]; .id == $d))
    | .tabs[] | select(.is_active) | .windows[] | select(.is_active)][0].id // empty'
}
# The deck tab's panes in layout order. kitty lists windows in creation
# order; moving a pane swaps its group, so read the groups.
demo_tab_order()  { demo_kitten ls | jq -c --argjson d ${DEMO_IDS[deck]:-0} '[.[].tabs[] | select(any(.windows[]; .id == $d)) | .groups[]?.windows[]]' }

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

# wait-own-tab NAME: wait until NAME is alone in a tab of its own, apart
# from the deck (the window may hold other tabs too, so don't count tabs).
wait-own-tab() {
  demo_dry wait-own-tab "$@" && return 0
  local id; id=$(demo_id $1) || return
  demo_poll "pane $1 to be alone in its own tab" demo_alone_in_tab $id
}
demo_alone_in_tab() {
  [[ $(demo_kitten ls | jq --argjson w $1 '[.[].tabs[] | select(any(.windows[]; .id == $w)) | .windows | length][0]') == 1 ]]
}

# adopt NAME MATCH: wait until exactly one window matches MATCH (kitty match
# syntax, e.g. var:demo=stray or cmdline:"(^|/)tidy-windows$": quote a regex
# with brackets, which kitty otherwise reads as grouping) and call it NAME.
# Not added to the cleanup list: a session or a tool opened it.
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

# wait-any-gone NAME...: wait until at least one of the NAMEd windows has
# closed (tidy-windows may close one or both of two duplicates).
wait-any-gone() {
  demo_dry wait-any-gone "$@" && return 0
  local -a ids; local n
  for n in "$@"; do ids+=($(demo_id $n)) || return; done
  demo_poll "one of $* to close" demo_any_gone $ids
}
demo_any_gone() {
  local id
  for id in "$@"; do demo_window_gone $id && return 0; done
  return 1
}

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

# demo_snapshot: one line per tab with its layout and windows (id, * for
# focused, title), then the last lines of the tab's focused pane (a tool's
# error there, like tidy-windows', would otherwise go when the demo cleans
# up), for play.log when a beat fails.
demo_snapshot() {
  local id line
  demo_kitten ls 2>/dev/null | jq -r '.[].tabs[] |
    "\([.windows[] | select(.is_focused) | .id][0] // "")\t" +
    "kitty: tab layout=\(.layout) windows=" +
    ([.windows[] | "\(.id)\(if .is_focused then "*" else "" end):\(.title)"] | join(" "))' |
  while IFS=$'\t' read -r id line; do
    print -r -- $line
    [[ -n $id ]] || continue
    demo_kitten get-text --match id:$id 2>/dev/null | grep -v '^[[:space:]]*$' | tail -8 | sed 's/^/  | /'
  done
}
