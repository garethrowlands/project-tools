#!/usr/bin/env zsh
# Tests for config/install.zsh, run against a temp $HOME (the real one is
# never touched).
#
#   zsh config/install-tests.zsh
#
# Exits 1 if any test fails.

ROOT=${0:A:h:h}
T=$(mktemp -d)
trap 'rm -rf $T' EXIT
fail=0

ok()  { print -r "PASS $1" }
bad() { print -r "FAIL $1"; fail=1 }
is()  { [[ $2 == "$3" ]] && ok $1 || bad "$1: got ${(q+)2}, want ${(q+)3}" }

H=$T/home
C=$H/.config
mkdir -p $C/kitty $C/btop/themes $C/mdfried
print -r -- 'foreground #cccccc' > $C/kitty/current-theme.conf
print -r -- 'font_family = "mine"' > $C/mdfried/config.toml
print -r -- $'#? btop\ncolor_theme = "Default"\ntheme_background = true' > $C/btop/btop.conf

HOME=$H XDG_CONFIG_HOME= zsh $ROOT/config/install.zsh > $T/out1 2>&1

want="include $ROOT/kitty/themes/catppuccin-mocha-crust.conf"
is 'kitty current-theme.conf includes the repo theme' "$(grep -x "include.*" $C/kitty/current-theme.conf)" $want
is 'kitty dark-theme.auto.conf is created' "$(grep -x "include.*" $C/kitty/dark-theme.auto.conf)" $want
is 'the old kitty theme is kept' "$(<$C/kitty/current-theme.conf.pre-symlink)" 'foreground #cccccc'
is 'btop theme is a link into the repo' "$(readlink $C/btop/themes/catppuccin_mocha.theme)" $ROOT/config/btop/themes/catppuccin_mocha.theme
is 'mdfried config is a link into the repo' "$(readlink $C/mdfried/config.toml)" $ROOT/config/mdfried/config.toml
is 'the old mdfried config is kept' "$(<$C/mdfried/config.toml.pre-symlink)" 'font_family = "mine"'
is 'btop color_theme is set' "$(grep '^color_theme' $C/btop/btop.conf)" 'color_theme = "catppuccin_mocha"'
is 'btop.conf keeps its other lines' "$(grep -c 'theme_background = true' $C/btop/btop.conf)" 1
is 'the old btop.conf is kept' "$(grep '^color_theme' $C/btop/btop.conf.pre-theme)" 'color_theme = "Default"'

# A second run changes nothing and says so.
cp -p $C/btop/btop.conf $T/btop.before
HOME=$H XDG_CONFIG_HOME= zsh $ROOT/config/install.zsh > $T/out2 2>&1
is 'a second run reports nothing moved, linked, written or edited' "$(grep -cE '^(moved|linked|wrote|edited)' $T/out2)" 0
is 'a second run leaves btop.conf alone' "$(cmp -s $C/btop/btop.conf $T/btop.before && echo same)" same

# With no btop.conf yet it is skipped, not created.
rm $C/btop/btop.conf
HOME=$H XDG_CONFIG_HOME= zsh $ROOT/config/install.zsh > $T/out3 2>&1
[[ ! -e $C/btop/btop.conf ]] && ok 'no btop.conf is created' || bad 'btop.conf was created'
is 'a missing btop.conf is reported' "$(grep -c '^skipped' $T/out3)" 1

exit $fail
