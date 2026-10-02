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
    done < <(fd --hidden --type d --max-depth 6 --glob '.git' "$root" 2>/dev/null)
  done < <(_project_parse_roots)

  [[ $show_progress -eq 1 ]] && printf '\r\033[K' >&2

  printf '%s\n' "${paths[@]}" | sort -u > "$cache_file"
}

_project_zoxide_scores() {
  # Outputs SCORE<TAB>DIR<TAB>KIND for every zoxide entry. KIND is "repo" for a
  # dir with a .git directory, "wt:MAIN" for a linked worktree (resolved from
  # its .git file's "gitdir: MAIN/.git/worktrees/NAME"), else empty (plain
  # dirs, submodules). Outputs nothing if zoxide isn't installed.
  whence zoxide >/dev/null || return 0
  local score dir kind line gitdir
  # zoxide also tries to age its database on query; a failed write is harmless.
  zoxide query --list --score 2>/dev/null | while read -r score dir; do
    kind=""
    if [[ -d "$dir/.git" ]]; then
      kind=repo
    elif [[ -f "$dir/.git" ]] && read -r line < "$dir/.git"; then
      gitdir="${line#gitdir: }"
      [[ "$gitdir" != /* ]] && gitdir="${${:-$dir/$gitdir}:a}"
      [[ "$gitdir" == */.git/worktrees/* ]] && kind="wt:${gitdir%/.git/worktrees/*}"
    fi
    printf '%s\t%s\t%s\n' "$score" "$dir" "$kind"
  done
}

_project_build_list() {
  # Outputs PATH<TAB>LABEL lines for fzf, with group headers (empty PATH field).
  # Args: cache_file [kitty_cwds] [zoxide_scores]
  # kitty_cwds: newline-separated list of open cwds; empty = skip open detection.
  # zoxide_scores: _project_zoxide_scores output; empty = alphabetical order.
  local cache_file="$1"
  local kitty_cwds="${2:-}"
  local zoxide_scores="${3:-}"

  # BSD awk rejects newlines in -v values, so roots, cwds and scores are fed as
  # file input via a single process substitution, separated by "---" sentinels.
  # FNR==NR identifies this first file; the cache is the second file.
  # Emits GROUP<TAB>SCORE<TAB>LABEL<TAB>PATH rows, sorted then formatted below.
  awk -F '\t' '
  function make_label(path,    i, pfx, home) {
    for (i = 1; i <= n_roots; i++) {
      pfx = root_arr[i] "/"
      if (substr(path, 1, length(pfx)) == pfx)
        return substr(path, length(pfx) + 1)
    }
    home = ENVIRON["HOME"] "/"
    if (home != "/" && substr(path, 1, length(home)) == home)
      return "~/" substr(path, length(home) + 1)
    return path
  }
  function add_repo(path) {
    if (!(path in is_repo)) { is_repo[path] = 1; paths[++n] = path }
  }
  function parent(p) {
    sub(/\/[^\/]*$/, "", p)
    return p
  }
  # Walks up from dir to the repos containing it (a worktree counts as its
  # main repo). Fills found[1..] innermost first; returns how many.
  function owners(dir,    p, k) {
    k = 0
    for (p = dir; p != ""; p = parent(p)) {
      if (p in wt_main)      found[++k] = wt_main[p]
      else if (p in is_repo) found[++k] = p
    }
    return k
  }
  FNR == NR {
    if ($0 == "---") { section++; next }
    if (!NF) next
    if (section == 0)      root_arr[++n_roots] = $0
    else if (section == 1) cwd_arr[++n_cwds] = $0
    else {
      z_score[++n_z] = $1; z_dir[n_z] = $2
      if ($3 == "repo") add_repo($2)
      else if (substr($3, 1, 3) == "wt:") { wt_main[$2] = substr($3, 4); add_repo(wt_main[$2]) }
    }
    next
  }
  NF { add_repo($0) }
  END {
    for (i = 1; i <= n_z; i++)
      if (owners(z_dir[i])) score[found[1]] += z_score[i]
    for (i = 1; i <= n_cwds; i++)
      for (k = owners(cwd_arr[i]); k > 0; k--) open[found[k]] = 1
    for (i = 1; i <= n; i++) {
      p = paths[i]
      printf "%d\t%.4f\t%s\t%s\n", (p in open) ? 0 : 1, score[p] + 0, make_label(p), p
    }
  }
  ' <({ _project_parse_roots; print -- '---'; print -r -- "$kitty_cwds"; print -- '---'; print -r -- "$zoxide_scores"; }) "$cache_file" \
  | LC_ALL=C sort -t $'\t' -k1,1n -k2,2gr -k3,3 \
  | awk -F '\t' '
  $1 == 0 && !open_hdr { print "\t── Open ──"; open_hdr = 1 }
  $1 == 1 && !all_hdr  { print "\t── All ──";  all_hdr = 1 }
  { print $4 "\t" ($1 == 0 ? "* " : "") $3 }
  END { if (!all_hdr) print "\t── All ──" }
  '
}

_project_preview_windows() {
  local dir="$1" ls_file="${2:-}"
  [[ -z "$ls_file" || ! -f "$ls_file" ]] && return
  jq -r --arg p "$dir" '
    [.[].tabs[].windows[] |
     select([.foreground_processes[].cwd // empty] | map(. == $p or startswith($p + "/")) | any)] |
    if length == 0 then empty
    else
      "[1mWindows[0m",
      (.[] | "[1m  \(.foreground_processes[0].cmdline[0] // "?" | ltrimstr("-"))  \(.foreground_processes[0].cwd // $p | if . == $p then "." else ltrimstr($p + "/") end)[0m")
    end
  ' "$ls_file" 2>/dev/null
}

_project_preview_dir() {
  local dir="$1" ls_file="${2:-}"
  [[ -z "$dir" ]] && return
  local windows
  windows=$(_project_preview_windows "$dir" "$ls_file")
  if [[ -n "$windows" ]]; then
    printf '%s\n%s\n\n' "$windows" "$(printf '%.0s─' $(seq 1 ${FZF_PREVIEW_COLUMNS:-40}))"
  fi
  local bat_width=${FZF_PREVIEW_COLUMNS:-80}
  if [[ -f "$dir/README.md" ]]; then
    bat --color=always --style=header --terminal-width "$bat_width" "$dir/README.md"
  elif [[ -f "$dir/CLAUDE.md" ]]; then
    bat --color=always --style=header --terminal-width "$bat_width" "$dir/CLAUDE.md"
  else
    ls "$dir"
  fi
}

_project_picker() {
  local query="${1:-}" cache_file="${2:-}" new_tab_key="${3:-}"
  local kitty_cwds="" kitty_ls_file=""

  if kitty @ ls &>/dev/null 2>&1; then
    local kitty_ls_json
    kitty_ls_json=$(kitty @ ls 2>/dev/null) || true
    kitty_cwds=$(printf '%s' "$kitty_ls_json" \
      | jq -r '.[].tabs[].windows[].foreground_processes[].cwd // empty' 2>/dev/null \
      | sort -u) || true
    kitty_ls_file=$(mktemp /tmp/project-kitty-XXXXXX)
    printf '%s' "$kitty_ls_json" > "$kitty_ls_file"
  fi

  local header='enter: open  ctrl-i: ide  ctrl-w: close  ctrl-y: copy'
  local -a extra_bindings=()
  if [[ -n "$new_tab_key" ]]; then
    header='enter: open  ctrl-t: new tab  ctrl-i: ide  ctrl-w: close  ctrl-y: copy'
    extra_bindings=(--bind 'ctrl-t:transform([[ -n {1} ]] && echo "become(echo newtab:{1})")')
  fi

  local preview_cmd="zsh -c 'source \"\$1\"; _project_preview_dir \"\$2\" \"\$3\"' -- ${_PROJECT_ZSH_PATH:q} {1} ${kitty_ls_file:q}"

  local result
  result=$(
    _project_build_list "$cache_file" "$kitty_cwds" "$(_project_zoxide_scores)" | fzf \
      --query "$query" \
      --prompt='Project> ' \
      --delimiter $'\t' \
      --with-nth 2 \
      --no-sort \
      --header="$header" \
      --preview "$preview_cmd" \
      --preview-window 'right:50%:wrap' \
      --bind 'enter:transform([[ -n {1} ]] && echo "become(echo {1})")' \
      --bind 'ctrl-i:execute-silent([[ -n {1} ]] && ide {1})' \
      --bind 'ctrl-w:execute-silent([[ -n {1} ]] && close-project {1})' \
      --bind 'ctrl-y:execute-silent([[ -n {1} ]] && echo -n {1} | pbcopy)' \
      "${extra_bindings[@]}"
  )

  [[ -n "$kitty_ls_file" ]] && rm -f "$kitty_ls_file"
  echo "$result"
}

current-project() {
  git rev-parse --show-toplevel 2>/dev/null
}

project() {
  local refresh=0 new_tab_key=""
  local -a query_parts=()
  local arg
  for arg in "$@"; do
    if [[ "$arg" == "--refresh" ]]; then
      refresh=1
    elif [[ "$arg" == "--new-tab-key" ]]; then
      new_tab_key=1
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

  if [[ ! -t 0 ]] && kitty @ ls &>/dev/null 2>&1; then
    local fifo
    fifo=$(mktemp -u /tmp/project-XXXXXX)
    mkfifo "$fifo"

    kitty @ launch --type=tab \
      --env "PROJECT_FIFO=$fifo" \
      --env "PROJECT_QUERY=$query" \
      --env "PROJECT_ROOTS=$PROJECT_ROOTS" \
      --env "PROJECT_CACHE=$cache_file" \
      --env "PROJECT_ZSH_PATH=$_PROJECT_ZSH_PATH" \
      --env "PROJECT_NEW_TAB_KEY=$new_tab_key" \
      zsh -c 'source "$PROJECT_ZSH_PATH"; result=$(_project_picker "$PROJECT_QUERY" "$PROJECT_CACHE" "${PROJECT_NEW_TAB_KEY:-}"); echo "$result" > "$PROJECT_FIFO"' > /dev/null
    open -a kitty

    read -r result < "$fifo"
    rm -f "$fifo"
  else
    result=$(_project_picker "$query" "$cache_file" "$new_tab_key")
  fi

  [[ -n "$result" ]] && echo "$result"
}
