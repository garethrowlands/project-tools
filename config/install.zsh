#!/usr/bin/env zsh
# Link the files in config/ to where the tools read them, and point kitty and
# btop at the Catppuccin Mocha theme. Safe to run again: anything that is
# already right is left alone, and a real file in the way is moved aside to
# NAME.pre-symlink first (the original is never lost).
#
#   zsh config/install.zsh
#
# Honours $HOME and $XDG_CONFIG_HOME, so it can be tried against a temp home.

ROOT=${0:A:h:h}
CONFIG=${XDG_CONFIG_HOME:-$HOME/.config}

link() {   # link SOURCE TARGET
  local src=$1 dst=$2
  mkdir -p ${dst:h}
  if [[ -L $dst && ${dst:A} == ${src:A} ]]; then
    print "ok       $dst"
    return
  fi
  if [[ -e $dst || -L $dst ]]; then
    mv $dst $dst.pre-symlink && print "moved    $dst -> $dst.pre-symlink"
  fi
  ln -s $src $dst && print "linked   $dst"
}

# kitty reads current-theme.conf and dark-theme.auto.conf, each just an
# include of the theme in the repo.
for f in current-theme.conf dark-theme.auto.conf; do
  dst=$CONFIG/kitty/$f
  want="include $ROOT/kitty/themes/catppuccin-mocha-crust.conf"
  if [[ -f $dst ]] && grep -qxF $want $dst; then
    print "ok       $dst"
    continue
  fi
  mkdir -p ${dst:h}
  [[ -e $dst ]] && mv $dst $dst.pre-symlink && print "moved    $dst -> $dst.pre-symlink"
  printf '# vim:ft=kitty\n## name: Catppuccin Mocha (crust)\n%s\n' $want > $dst && print "wrote    $dst"
done

link $ROOT/config/btop/themes/catppuccin_mocha.theme $CONFIG/btop/themes/catppuccin_mocha.theme
link $ROOT/config/mdfried/config.toml $CONFIG/mdfried/config.toml

# btop rewrites its own btop.conf, so it is edited in place, not linked.
btop_conf=$CONFIG/btop/btop.conf
if [[ -f $btop_conf ]]; then
  if grep -qx 'color_theme = "catppuccin_mocha"' $btop_conf; then
    print "ok       $btop_conf"
  else
    sed -i.pre-theme -e 's/^color_theme = .*/color_theme = "catppuccin_mocha"/' $btop_conf &&
      print "edited   $btop_conf (original kept as btop.conf.pre-theme)"
  fi
else
  print "skipped  $btop_conf (btop has not run yet; set color_theme = \"catppuccin_mocha\" in it)"
fi

print "Reload kitty's config (ctrl+shift+f5) to pick up the theme."
