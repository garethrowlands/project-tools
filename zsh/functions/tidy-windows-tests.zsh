#!/usr/bin/env zsh
# Tests for zsh/bin/tidy-windows' apply step: the real script, run against a
# fake advise (one close and one move recommendation) and fake kitty and fzf
# on PATH that record what they're given. Needs neither kitty nor the API.
#
#   zsh zsh/functions/tidy-windows-tests.zsh
#
# Exits 1 if any test fails.

ROOT=${0:A:h:h:h}
T=$(mktemp -d)
trap 'rm -rf $T' EXIT
fail=0

ok()  { print -r "PASS $1" }
bad() { print -r "FAIL $1"; fail=1 }
is()  { [[ $2 == "$3" ]] && ok $1 || bad "$1: got ${(q+)2}, want ${(q+)3}" }

# tidy-windows finds advise at ../../python/tidy-windows-advise/advise from
# its own directory, so it runs from a copy laid out the same way
mkdir -p $T/zsh/bin $T/python/tidy-windows-advise $T/bin
cp $ROOT/zsh/bin/tidy-windows $T/zsh/bin/
print -r -- '#!/bin/zsh
cat >/dev/null
print -r -- $'"'"'5\tclose\t\t[CLOSE] docs\n7\tmove\t2\t[MOVE→tab 2] shop-api\n9\tmove\tnew:foo\t[MOVE→new foo tab] foo\n10\tmove\tnew:foo\t[MOVE→new foo tab] foo'"'"'' >| $T/python/tidy-windows-advise/advise
print -r -- '#!/bin/zsh
print -r -- "$*" >> '$T'/kitty.calls
[[ $2 == detach-window && $6 == new ]] && : >| '$T'/made-tab
if [[ $1 == @ && $2 == ls ]]; then
  # once a window has been sent to a new tab, window 9 is in tab 42
  if [[ -e '$T'/made-tab ]]; then
    print -r -- "[{\"tabs\":[{\"id\":42,\"windows\":[{\"id\":9}]}]}]"
  else
    print -r -- "[]"
  fi
fi
return 0' >| $T/bin/kitty
print -r -- '#!/bin/zsh
cat' >| $T/bin/fzf
chmod +x $T/python/tidy-windows-advise/advise $T/bin/kitty $T/bin/fzf

# zsh -f: the user's ~/.zshenv would put the real kitty back first on PATH
PATH=$T/bin:$PATH zsh -f $T/zsh/bin/tidy-windows >$T/out 2>&1 </dev/null
is 'tidy-windows applies both rows' "$(tail -1 $T/out)" 'tidy-windows: closed 1, moved 3'
grep -qx '@ close-window --match id:5' $T/kitty.calls && ok 'close targets the window by id' || bad "close call: $(grep close $T/kitty.calls)"
# kitty's --target-tab takes a match expression, and without --stay-in-tab
# kitty would switch to the target tab: tidy-windows leaves you where you
# launched it
grep -qx '@ detach-window --match id:7 --target-tab id:2 --stay-in-tab' $T/kitty.calls \
  && ok 'move targets the tab by id: match, staying in this tab' || bad "move call: $(grep detach $T/kitty.calls)"

# a project with no tab of its own gets a new one, titled with its name; its other
# windows then follow into that tab rather than each making another
grep -qx '@ detach-window --match id:9 --target-tab new --stay-in-tab' $T/kitty.calls \
  && ok 'first window of a new project tab is detached to a new tab' || bad "new tab call: $(grep detach $T/kitty.calls)"
grep -qx '@ set-tab-title --match id:42 foo' $T/kitty.calls \
  && ok 'the new tab is titled with the project name' || bad "title call: $(grep set-tab-title $T/kitty.calls)"
grep -qx '@ detach-window --match id:10 --target-tab id:42 --stay-in-tab' $T/kitty.calls \
  && ok 'the next window of that project joins the tab just made' || bad "join call: $(grep 'id:10' $T/kitty.calls)"

exit $fail
