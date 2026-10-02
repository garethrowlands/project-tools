# kitty-cd-link: lets ~/.config/kitty/open_local.py change this shell's
# directory when a local directory hyperlink is clicked in kitty.
#
# Protocol: the kitten writes  ESC [ 2 9 2 7 1 ~  <hex of UTF-8 path>  BEL
# to the tty. The trigger key runs _kitty_cd_link, which switches to a private
# keymap that accumulates hex digits until BEL, then cds. Hex keeps arbitrary
# names (spaces, quotes, newlines, Unicode, metacharacters) out of the parser.
# The kitten only sends when kitty reports a prompt, the screen is not in the
# alternate buffer, and the tty's foreground process is the zsh that last
# announced itself via the kitty_cd_link_pid user var.

[[ -o interactive && -n $KITTY_WINDOW_ID ]] || return 0

typeset -g _kitty_cd_link_hex='' _kitty_cd_link_prev_keymap=''
typeset -g _kitty_cd_link_pid64=$(print -n $$ | base64)

typeset -g _kitty_cd_link_editor=$'\0'

_kitty_cd_link_announce() {
  # OSC 1337 SetUserVar: kitty stores it on the window as user_vars.
  print -n "\e]1337;SetUserVar=kitty_cd_link_pid=$_kitty_cd_link_pid64\a"
  # Also publish $EDITOR (only when it changes): kitty can only see a shell's
  # environment as it was at exec time, not variables exported in .zshrc, so
  # open_local.py passes this to the micro/glow/yazi overlays it launches.
  if [[ ${EDITOR-} != $_kitty_cd_link_editor ]]; then
    _kitty_cd_link_editor=${EDITOR-}
    print -n "\e]1337;SetUserVar=kitty_editor=$(print -rn -- $_kitty_cd_link_editor | base64 | tr -d '\n')\a"
  fi
}

# Hex string -> raw bytes in REPLY.
_kitty_cd_link_decode() {
  emulate -L zsh -o extended_glob
  [[ $1 == ([0-9a-f][0-9a-f])## ]] || return 1
  # Every byte becomes \xNN, then print -v interprets just those escapes.
  print -v REPLY -- "${1//(#b)(??)/\\x$match[1]}"
}

_kitty_cd_link() {
  _kitty_cd_link_hex=''
  _kitty_cd_link_prev_keymap=$KEYMAP
  zle -K kitty-cd-link
}

_kitty_cd_link_digit() {
  _kitty_cd_link_hex+=$KEYS
}

_kitty_cd_link_abort() {
  # Any unexpected key while reading the payload: discard it.
  _kitty_cd_link_hex=''
  zle -K ${_kitty_cd_link_prev_keymap:-main}
}

_kitty_cd_link_done() {
  emulate -L zsh -o extended_glob
  zle -K ${_kitty_cd_link_prev_keymap:-main}
  local hex=$_kitty_cd_link_hex dir
  _kitty_cd_link_hex=''
  if (( ${#hex} == 0 || ${#hex} % 2 )); then
    zle -M "kitty-cd: malformed link payload"
    return 1
  fi
  _kitty_cd_link_decode $hex || { zle -M "kitty-cd: could not decode path"; return 1 }
  dir=$REPLY
  if [[ $CONTEXT != start || -n $PREBUFFER ]]; then
    zle -M "kitty-cd: not at a fresh prompt; not changing directory"
    return 1
  fi
  if [[ $dir != /* || ! -d $dir ]]; then
    zle -M "kitty-cd: not a directory: ${(q+)dir}"
    return 1
  fi
  # BUFFER and CURSOR are left alone, so a partly typed command survives.
  builtin cd -- "$dir" || { zle -M "kitty-cd: cd failed: ${(q+)dir}"; return 1 }
  # Refresh the prompt (p10k etc.) the way fzf's cd widget does.
  local fn
  for fn in precmd $precmd_functions; do
    (( $+functions[$fn] )) && "$fn"
  done
  zle .reset-prompt
}

zle -N _kitty_cd_link
zle -N _kitty_cd_link_digit
zle -N _kitty_cd_link_abort
zle -N _kitty_cd_link_done

bindkey -N kitty-cd-link
bindkey -M kitty-cd-link -R '\x00-\xff' _kitty_cd_link_abort 2>/dev/null
bindkey -M kitty-cd-link -R '0-9' _kitty_cd_link_digit
bindkey -M kitty-cd-link -R 'a-f' _kitty_cd_link_digit
bindkey -M kitty-cd-link '\a' _kitty_cd_link_done
() {
  local km
  for km in emacs viins vicmd; do
    bindkey -M $km '\e[29271~' _kitty_cd_link
  done
}

autoload -Uz add-zsh-hook
add-zsh-hook precmd _kitty_cd_link_announce
