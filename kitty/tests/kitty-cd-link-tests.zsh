#!/usr/bin/env zsh
# Tests for kitty-cd-link.zsh: path decoding and key bindings.
#
#   zsh kitty/tests/kitty-cd-link-tests.zsh
#
# Exits 1 if any test fails. Runs an interactive zsh without your rc files
# (zsh -f) so ZLE is available.

if [[ -z $_KITTY_CD_LINK_TEST_INNER ]]; then
  exec env _KITTY_CD_LINK_TEST_INNER=1 KITTY_WINDOW_ID=1 zsh -f -i -c "source ${(q)0:A}"
fi

source ${0:A:h:h}/kitty-cd-link.zsh
fail=0

ok()  { print -r "PASS $1" }
bad() { print -r "FAIL $1"; fail=1 }

for n in plain 'with space' "it's" 'dq"uote' 'back\slash' 'dollar$HOME' '$(touch PWNED)' '`id`' \
         ';rm -rf x;' 'glob*?[x]' 'ünïcødé 日本 🎉' $'new\nline' $'tab\there' '-dash' '~tilde' '!bang' \
         '%pct{x}' 'a&b|c<d>e' ' sp ' '\x41\n\c'; do
  hex=$(print -rn -- "/tmp/$n" | xxd -p | tr -d '\n')
  if _kitty_cd_link_decode $hex && [[ $REPLY == "/tmp/$n" ]]; then ok "decode ${(q+)n}"; else bad "decode ${(q+)n} -> ${(q+)REPLY}"; fi
done
for malformed in '' 'abc' '2F' 'zz' '2f 74'; do
  _kitty_cd_link_decode $malformed && bad "accepted ${(q+)malformed}" || ok "rejected ${(q+)malformed}"
done

[[ $(bindkey -M emacs '\e[29271~') == *_kitty_cd_link ]] && ok 'trigger bound in emacs keymap' || bad 'trigger not bound'
[[ $(bindkey -M kitty-cd-link '\a') == *_kitty_cd_link_done ]] && ok 'BEL ends the payload' || bad 'BEL not bound'
(( ${precmd_functions[(I)_kitty_cd_link_announce]} )) && ok 'announce hook installed' || bad 'announce hook missing'

# The announcement: pid every prompt, $EDITOR only when it changes.
EDITOR=micro
out=$(_kitty_cd_link_announce; _kitty_cd_link_announce)
[[ $out == *kitty_editor=$(print -rn micro | base64)* && ${#${(ps:kitty_editor=:)out}} -eq 2 ]] \
  && ok 'EDITOR announced once while unchanged' || bad "EDITOR announcement: ${(q+)out}"

exit $fail
