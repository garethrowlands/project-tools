source "$HOME/.config/zsh/functions/notes-lib.zsh"

web() {
  local query="${*:-}" result

  if [ "$TERM" = "xterm-kitty" ] && kitty @ ls &>/dev/null 2>&1; then
    local fifo
    fifo=$(mktemp -u /tmp/web-XXXXXX)
    mkfifo "$fifo"

    kitty @ launch --type=tab \
      --env "WEB_FIFO=$fifo" \
      --env "WEB_QUERY=$query" \
      zsh -c 'source "$HOME/.config/zsh/functions/web.zsh"; result=$(_notes_picker "$WEB_QUERY"); echo "$result" > "$WEB_FIFO"' > /dev/null
    open -a kitty

    read -r result < "$fifo"
    rm -f "$fifo"
  else
    result=$(_notes_picker "$query")
  fi

  [ -z "$result" ] && return

  local title url
  title=$(rg -m1 -A3 "^title: " "$result" | awk '/^title: >-$/{y=1;t="";next} y&&/^  /{sub(/^[[:space:]]+/,"");sub(/[[:space:]]+$/,"");t=t==""?$0:t" "$0;next} y{if(t!="")print t;exit} /^title: /{sub(/^title: /,"");print;exit} END{if(y&&t!="")print t}')
  url=$(rg -m1 -A1 "^(source|url): " "$result" | grep -oE "https?://[^[:space:]\"]+" | head -1)

  [ -z "$url" ] && { echo "No source/url found in: $result"; return 1; }
  [ -z "$title" ] && title="$url"

  if [ -t 1 ]; then
    printf "\033]8;;%s\033\\\\%s\033]8;;\033\\\\\n" "$url" "$title"
  else
    echo "$url"
  fi
}

note() {
  local query="${*:-}" result

  if [ "$TERM" = "xterm-kitty" ] && kitty @ ls &>/dev/null 2>&1; then
    local fifo
    fifo=$(mktemp -u /tmp/note-XXXXXX)
    mkfifo "$fifo"

    kitty @ launch --type=tab \
      --env "NOTE_FIFO=$fifo" \
      --env "NOTE_QUERY=$query" \
      zsh -c 'source "$HOME/.config/zsh/functions/web.zsh"; result=$(_notes_picker "$NOTE_QUERY"); echo "$result" > "$NOTE_FIFO"' > /dev/null
    open -a kitty

    read -r result < "$fifo"
    rm -f "$fifo"
  else
    result=$(_notes_picker "$query")
  fi

  [ -z "$result" ] && return
  if [ -t 1 ]; then
    printf "\033]8;;file://%s\033\\\\%s\033]8;;\033\\\\\n" "$result" "$result"
  else
    echo "$result"
  fi
}
