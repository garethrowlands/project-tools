_notes_extract_titles() {
  local vault="${1:-$HOME/notes}"
  # -A2 captures one continuation line for both >- block scalars and flow scalars that wrap
  rg --glob '*.md' --no-heading --no-line-number -m1 -A2 '^title: ' "$vault" |
    awk '
      /^--$/ { lf=""; lv=""; lmode=""; next }
      { n=index($0,":title: ") }
      n>0 {
        f=substr($0,1,n-1); v=substr($0,n+8); sub(/[[:space:]]+$/,"",v)
        if (v==">-") {
          lf=f; lv=""; lmode="block"
        } else if (substr(v,1,1)=="\"" && substr(v,length(v),1)=="\"" && length(v)>=2) {
          print f "\tT\t" substr(v,2,length(v)-2); lf=""; lv=""; lmode=""
        } else if (substr(v,1,1)=="\"") {
          lf=f; lv=substr(v,2); lmode="flow"
        } else {
          print f "\tT\t" v; lf=""; lv=""; lmode=""
        }
        next
      }
      lmode=="block" {
        p=lf "-"
        if (index($0,p)==1) { line=substr($0,length(p)+1); sub(/^[[:space:]]+/,"",line); sub(/[[:space:]]+$/,"",line); if(line!="") print lf "\tT\t" line }
        lf=""; lv=""; lmode=""
      }
      lmode=="flow" {
        p=lf "-"
        if (index($0,p)==1) {
          line=substr($0,length(p)+1); sub(/^[[:space:]]+/,"",line); sub(/"[[:space:]]*$/,"",line)
          combined=lv " " line; sub(/[[:space:]]+$/,"",combined)
          if (combined!="") print lf "\tT\t" combined
        }
        lf=""; lv=""; lmode=""
      }
    '
}

_notes_extract_excerpts() {
  local vault="${1:-$HOME/notes}"
  rg --glob '*.md' --no-heading --no-line-number -A1 '^> ## Excerpt' "$vault" |
    grep -- '->' |
    awk '{ n=index($0,"->"); e=substr($0,n+2); sub(/^ /,"",e); if(length(e)>100) e=substr(e,1,100) "…"; print substr($0,1,n-1) "\tE\t" e }'
}

# Outputs filepath::title [— excerpt] for notes that have a frontmatter title.
_notes_title_list() {
  local vault="${1:-$HOME/notes}"
  { _notes_extract_titles "$vault"; _notes_extract_excerpts "$vault"; } | awk -F'\t' '
    $2=="T" { titles[$1]=$3 }
    $2=="E" { excerpts[$1]=$3 }
    END {
      for (f in titles) {
        if (f in excerpts) print f "::" titles[f] " \342\200\224 " excerpts[f]
        else print f "::" titles[f]
      }
    }
  ' | sort
}

# Outputs filepath::title [— excerpt] for all .md files; untitled files use basename.
_notes_all_list() {
  local vault="${1:-$HOME/notes}"
  {
    _notes_extract_titles "$vault"
    _notes_extract_excerpts "$vault"
    rg --files --glob '*.md' "$vault" | awk '{ print $0 "\tF\t" }'
  } | awk -F'\t' '
    $2=="T" { titles[$1]=$3 }
    $2=="E" { excerpts[$1]=$3 }
    $2=="F" { all[$1]=1 }
    END {
      for (f in all) {
        title = titles[f]
        if (title == "") {
          n = split(f, parts, "/"); base = parts[n]; sub(/\.md$/, "", base); title = base
        }
        if (f in excerpts) print f "::" title " \342\200\224 " excerpts[f]
        else print f "::" title
      }
    }
  ' | sort
}

# Writes a filepath<TAB>title map to a temp file and prints its path.
# Caller must rm -f the returned path.
_notes_title_map_file() {
  local vault="${1:-$HOME/notes}"
  local tmp; tmp=$(mktemp)
  _notes_extract_titles "$vault" | awk -F'\t' '$2=="T"{print $1 "\t" $3}' | sort > "$tmp"
  echo "$tmp"
}

_notes_picker() {
  local query="${1:-}" mode="title"
  local vault="$HOME/notes"
  local map_file; map_file=$(_notes_title_map_file "$vault")

  local awk_join='NR==FNR{t[$1]=$2;next}{n=split($1,a,"/");b=a[n];sub(/\.md$/,"",b);print $1"::"(($1 in t)?t[$1]:b)}'

  local reload_body
  printf -v reload_body \
    '([ -n {q} ] && rg -l --glob '"'"'*.md'"'"' -e {q} %s 2>/dev/null || rg --files --glob '"'"'*.md'"'"' %s) | awk -F'"'"'\t'"'"' '"'"'%s'"'"' %s -' \
    "$vault" "$vault" "$awk_join" "$map_file"

  local bind_obsidian
  printf -v bind_obsidian \
    'ctrl-b:execute-silent(f={1}; rel=${f#%s/}; open "obsidian://adv-uri?vault=notes&viewmode=preview&filepath=$(jq -rn --arg s "$rel" '"'"'$s|@uri'"'"')")' \
    "$vault"

  while true; do
    local result
    case "$mode" in
      title)
        result=$(
          _notes_all_list "$vault" | fzf \
            --query "$query" \
            --prompt='Title> ' \
            --delimiter '::' \
            --header=$'ctrl-o: browser | ctrl-e: VS Code | ctrl-b: Obsidian | ctrl-r: body search | enter: print path' \
            --preview 'bat --style=numbers --color=always {1}' \
            --bind 'ctrl-o:execute-silent(url=$(rg -m1 -A1 "^(source|url): " {1} | grep -oE "https?://[^[:space:]\"]+" | head -1); [ -n "$url" ] && open "$url")' \
            --bind 'ctrl-e:execute-silent(code {1})' \
            --bind "$bind_obsidian" \
            --bind 'ctrl-r:become(printf "§body§%s" {q})' \
            --bind 'enter:become(echo {1})'
        )
        ;;
      body)
        result=$(
          rg --files --glob '*.md' "$vault" \
            | awk -F'\t' "$awk_join" "$map_file" - \
            | fzf \
                --query "$query" \
                --prompt='Body> ' \
                --delimiter '::' \
                --header=$'ctrl-o: browser | ctrl-e: VS Code | ctrl-b: Obsidian | ctrl-r: title search | enter: print path' \
                --preview 'bat --style=numbers --color=always {1}' \
                --bind "change:reload($reload_body)" \
                --bind 'ctrl-o:execute-silent(url=$(rg -m1 -A1 "^(source|url): " {1} | grep -oE "https?://[^[:space:]\"]+" | head -1); [ -n "$url" ] && open "$url")' \
                --bind 'ctrl-e:execute-silent(code {1})' \
                --bind "$bind_obsidian" \
                --bind 'ctrl-r:become(printf "§title§%s" {q})' \
                --bind 'enter:become(echo {1})'
        )
        ;;
    esac

    case "$result" in
      '§body§'*)  mode="body";  query="${result#§body§}"  ;;
      '§title§'*) mode="title"; query="${result#§title§}" ;;
      *)          rm -f "$map_file"; [[ -n "$result" ]] && echo "$result"; return ;;
    esac
  done
}
