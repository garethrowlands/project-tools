# project.zsh — interactive git project picker
# Source this file to get the `project` function.

_project_cache_file() {
  echo "${XDG_CACHE_HOME:-$HOME/.cache}/project-tools/projects.txt"
}

_project_expand_tilde() {
  local r="$1"
  [[ "$r" == "~" ]]    && r="$HOME"
  [[ "$r" == "~/"* ]]  && r="$HOME/${r:2}"
  echo "$r"
}

_project_parse_roots() {
  local -a roots=("${(@s/:/)PROJECT_ROOTS}")
  local root
  for root in "${roots[@]}"; do
    [[ -z "$root" ]] && continue
    echo "$(_project_expand_tilde "$root")"
  done
}

_project_rel_label() {
  local abs_path="$1"
  local -a roots=("${(@s/:/)PROJECT_ROOTS}")
  local root root_prefix
  for root in "${roots[@]}"; do
    root="$(_project_expand_tilde "$root")"
    root_prefix="$root/"
    if [[ "$abs_path" == "$root_prefix"* ]]; then
      echo "${abs_path#$root_prefix}"
      return
    fi
  done
  echo "$abs_path"
}

_project_scan() {
  local cache_file="$1"
  mkdir -p "${cache_file:h}"
  {
    local root
    while IFS= read -r root; do
      [[ -d "$root" ]] || continue
      find "$root" -maxdepth 3 -name ".git" -type d 2>/dev/null | while IFS= read -r gitdir; do
        dirname "$gitdir"
      done
    done < <(_project_parse_roots)
  } | sort -u > "$cache_file"
}

_project_build_list() {
  # Outputs PATH<TAB>LABEL lines for fzf, with group headers (empty PATH field).
  # Args: cache_file [kitty_cwds]
  # kitty_cwds: newline-separated list of open cwds; empty = skip open detection.
  local cache_file="$1"
  local kitty_cwds="${2:-}"

  local -a open_paths
  if [[ -n "$kitty_cwds" ]]; then
    local path cwd
    while IFS= read -r path; do
      [[ -z "$path" ]] && continue
      while IFS= read -r cwd; do
        if [[ "$cwd" == "$path" || "$cwd" == "$path/"* ]]; then
          open_paths+=("$path")
          break
        fi
      done <<< "$kitty_cwds"
    done < "$cache_file"
  fi

  local -A open_set
  local p
  for p in "${open_paths[@]}"; do
    open_set[$p]=1
  done

  if (( ${#open_paths[@]} > 0 )); then
    printf '\t── Open ──\n'
    for p in "${open_paths[@]}"; do
      printf '%s\t%s\n' "$p" "$(_project_rel_label "$p")"
    done
  fi

  printf '\t── All ──\n'
  local path
  while IFS= read -r path; do
    [[ -z "$path" ]] && continue
    [[ -z "${open_set[$path]}" ]] && printf '%s\t%s\n' "$path" "$(_project_rel_label "$path")"
  done < "$cache_file"
}

_project_picker() {
  local query="${1:-}" cache_file="${2:-}"
  local kitty_cwds=""

  if [[ "$TERM" = "xterm-kitty" ]] && kitty @ ls &>/dev/null 2>&1; then
    kitty_cwds=$(kitty @ ls 2>/dev/null \
      | jq -r '.[].tabs[].windows[].foreground_processes[].cwd // empty' 2>/dev/null \
      | sort -u) || true
  fi

  local result
  result=$(
    _project_build_list "$cache_file" "$kitty_cwds" | fzf \
      --query "$query" \
      --prompt='Project> ' \
      --delimiter $'\t' \
      --with-nth 2 \
      --no-sort \
      --header=$'enter: open project' \
      --bind 'enter:transform([[ -n {1} ]] && echo "become(echo {1})")'
  )

  echo "$result"
}

project() {
  local query="${*:-}"

  if [[ -z "$PROJECT_ROOTS" ]]; then
    echo "project: PROJECT_ROOTS is not set or empty" >&2
    return 1
  fi

  local cache_file; cache_file=$(_project_cache_file)

  if [[ ! -f "$cache_file" ]]; then
    _project_scan "$cache_file"
  fi

  local result

  if [[ "$TERM" = "xterm-kitty" ]] && kitty @ ls &>/dev/null 2>&1; then
    local fifo
    fifo=$(mktemp -u /tmp/project-XXXXXX)
    mkfifo "$fifo"

    kitty @ launch --type=tab \
      --env "PROJECT_FIFO=$fifo" \
      --env "PROJECT_QUERY=$query" \
      --env "PROJECT_ROOTS=$PROJECT_ROOTS" \
      --env "PROJECT_CACHE=$cache_file" \
      zsh -c 'source "$HOME/.config/zsh/functions/project.zsh"; result=$(_project_picker "$PROJECT_QUERY" "$PROJECT_CACHE"); echo "$result" > "$PROJECT_FIFO"' > /dev/null
    open -a kitty

    read -r result < "$fifo"
    rm -f "$fifo"
  else
    result=$(_project_picker "$query" "$cache_file")
  fi

  [[ -n "$result" ]] && echo "$result"
}
