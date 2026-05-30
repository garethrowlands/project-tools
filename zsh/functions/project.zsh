# project.zsh — interactive git project picker
# Source this file to get the `project` function.
_PROJECT_ZSH_PATH="${0:A}"

_project_cache_file() {
  if [[ -n "${PROJECT_CACHE:-}" ]]; then
    local p="$PROJECT_CACHE"
    [[ "$p" == "~" ]]   && p="$HOME"
    [[ "$p" == "~/"* ]] && p="$HOME/${p:2}"
    echo "$p"
  else
    echo "${XDG_CACHE_HOME:-$HOME/.cache}/project-tools/projects.txt"
  fi
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
  local show_progress="${2:-0}"
  mkdir -p "${cache_file:h}"

  local count=0
  local -a paths=()

  local root
  while IFS= read -r root; do
    if [[ ! -d "$root" ]]; then
      [[ $show_progress -eq 1 ]] && printf '\r\033[K' >&2
      printf 'project: root not found, skipping: %s\n' "$root" >&2
      continue
    fi
    local gitdir
    while IFS= read -r gitdir; do
      paths+=("${gitdir:h}")
      (( count++ ))
      [[ $show_progress -eq 1 ]] && printf '\rScanning... %d repos found' "$count" >&2
    done < <(find "$root" -maxdepth 3 -name ".git" -type d 2>/dev/null)
  done < <(_project_parse_roots)

  [[ $show_progress -eq 1 ]] && printf '\r\033[K' >&2

  printf '%s\n' "${paths[@]}" | sort -u > "$cache_file"
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

_switch_project_find_window() {
  # Args: project_path kitty_ls_json
  # Outputs: "window:<id>" or "tab:<id>" or empty if no match found.
  local project_path="$1"
  local kitty_ls_json="$2"
  local project_basename="${project_path:t}"

  # user var match: explicit tag set by switch-project on previous visit (highest priority)
  local hit
  hit=$(printf '%s' "$kitty_ls_json" | jq -r --arg path "$project_path" '
    .[].tabs[].windows[] |
    select(.user_vars.project_path == $path) |
    "window:\(.id)"
  ' 2>/dev/null | head -1)
  [[ -n "$hit" ]] && { echo "$hit"; return; }

  # cwd match: any window with a foreground process cwd inside the project dir
  hit=$(printf '%s' "$kitty_ls_json" | jq -r --arg path "$project_path" '
    .[].tabs[].windows[] |
    select([.foreground_processes[].cwd] |
           map(. == $path or startswith($path + "/")) | any) |
    "window:\(.id)"
  ' 2>/dev/null | head -1)
  [[ -n "$hit" ]] && { echo "$hit"; return; }

  # title match on windows
  hit=$(printf '%s' "$kitty_ls_json" | jq -r --arg name "$project_basename" '
    .[].tabs[].windows[] |
    select(.title | contains($name)) |
    "window:\(.id)"
  ' 2>/dev/null | head -1)
  [[ -n "$hit" ]] && { echo "$hit"; return; }

  # title match on tabs
  hit=$(printf '%s' "$kitty_ls_json" | jq -r --arg name "$project_basename" '
    .[].tabs[] |
    select(.title | contains($name)) |
    "tab:\(.id)"
  ' 2>/dev/null | head -1)
  [[ -n "$hit" ]] && echo "$hit"
}

_detect_ide_command() {
  local path="$1"
  if [[ -f "$path/tspconfig.yaml" ]]; then
    echo "code"
  elif [[ -f "$path/package.json" ]]; then
    echo "code"
  elif [[ -f "$path/pom.xml" || -f "$path/build.gradle" || -f "$path/build.gradle.kts" || -d "$path/.idea" ]]; then
    echo "idea"
  fi
}

current-project() {
  [[ "$TERM" != "xterm-kitty" ]] && return 1
  kitty @ ls --self 2>/dev/null | jq -r '.[].tabs[].windows[].user_vars.project_path // empty'
}

switch-project() {
  local query="${*:-}"

  local project_path
  project_path=$(project "$query")
  [[ -z "$project_path" ]] && return 0

  local kitty_ls_json
  kitty_ls_json=$(kitty @ ls 2>/dev/null) || true

  if [[ -n "$kitty_ls_json" ]]; then
    local match
    match=$(_switch_project_find_window "$project_path" "$kitty_ls_json")

    if [[ -n "$match" ]]; then
      local match_type="${match%%:*}"
      local match_id="${match#*:}"
      if [[ "$match_type" == "window" ]]; then
        kitty @ focus-window --match "id:$match_id" 2>/dev/null || true
        kitty @ set-user-vars --match "id:$match_id" project_path="$project_path" 2>/dev/null || true
      else
        kitty @ focus-tab --match "id:$match_id" 2>/dev/null || true
      fi
      osascript -e 'tell application "kitty" to activate' 2>/dev/null || true
      local ide_cmd
      ide_cmd=$(_detect_ide_command "$project_path")
      [[ -n "$ide_cmd" ]] && "$ide_cmd" "$project_path" 2>/dev/null || true
    fi
  fi

  export PROJECT_PATH="$project_path"
  cd "$project_path"
  [[ "$TERM" == "xterm-kitty" ]] && \
    kitty @ set-user-vars --self project_path="$project_path" 2>/dev/null || true
}

project() {
  local refresh=0
  local -a query_parts=()
  local arg
  for arg in "$@"; do
    if [[ "$arg" == "--refresh" ]]; then
      refresh=1
    else
      query_parts+=("$arg")
    fi
  done
  local query="${query_parts[*]:-}"

  if [[ -z "$PROJECT_ROOTS" ]]; then
    echo "project: PROJECT_ROOTS is not set or empty" >&2
    return 1
  fi

  local cache_file; cache_file=$(_project_cache_file)

  if [[ $refresh -eq 1 ]]; then
    _project_scan "$cache_file" 1
  elif [[ ! -f "$cache_file" ]]; then
    _project_scan "$cache_file" 0
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
      --env "PROJECT_ZSH_PATH=$_PROJECT_ZSH_PATH" \
      zsh -c 'source "$PROJECT_ZSH_PATH"; result=$(_project_picker "$PROJECT_QUERY" "$PROJECT_CACHE"); echo "$result" > "$PROJECT_FIFO"' > /dev/null
    open -a kitty

    read -r result < "$fifo"
    rm -f "$fifo"
  else
    result=$(_project_picker "$query" "$cache_file")
  fi

  [[ -n "$result" ]] && echo "$result"
}
