# rdel: delayed-delete trash for zsh.
# Move files to a hidden trash bin, then permanently delete them after a
# configurable retention window.

unalias rdel 2>/dev/null || true

rdel() {
  emulate -L zsh
  setopt localoptions no_shwordsplit

  local -i verbose=0 force=0
  local retention_days=-1
  local trash_root="${RDEL_TRASH:-${XDG_DATA_HOME:-$HOME/.local/share}/rdel/.trash}"
  local -a sources
  local restore_id=""
  local subcommand=""

  while (( $# > 0 )); do
    case "$1" in
      --)
        shift
        sources+=("$@")
        break
        ;;
      -h|--help|help)
        _rdel_help
        return 0
        ;;
      -l|--list)
        subcommand=list
        shift
        ;;
      --restore)
        if (( $# < 2 )); then
          print -u2 -- "rdel: --restore requires an ID"
          return 1
        fi
        subcommand=restore
        restore_id="$2"
        shift 2
        ;;
      --empty)
        subcommand=empty
        shift
        ;;
      -v|--verbose)
        verbose=1
        shift
        ;;
      -f|--force)
        force=1
        shift
        ;;
      -d|--days)
        if (( $# < 2 )); then
          print -u2 -- "rdel: $1 requires a value"
          return 1
        fi
        retention_days="$2"
        shift 2
        ;;
      --days=*)
        retention_days="${1#--days=}"
        shift
        ;;
      -r|-R|--recursive)
        # Always recursive; accepted for rm compatibility.
        shift
        ;;
      -*)
        # Combined short options: -fv, -rfv, -d2, etc.
        local opts="${1#-}"
        local i c
        for (( i = 1; i <= ${#opts}; i++ )); do
          c="${opts:$i-1:1}"
          case "$c" in
            f) force=1 ;;
            v) verbose=1 ;;
            r|R) ;;
            l)
              subcommand=list
              ;;
            h)
              _rdel_help
              return 0
              ;;
            d)
              if (( i < ${#opts} )); then
                retention_days="${opts:$i}"
                break
              elif (( $# > 1 )) && [[ "$2" != -* ]]; then
                retention_days="$2"
                shift
                break
              else
                print -u2 -- "rdel: option requires a value -- 'd'"
                return 1
              fi
              ;;
            *)
              print -u2 -- "rdel: invalid option -- '$c'"
              return 1
              ;;
          esac
        done
        shift
        ;;
      *)
        sources+=("$1")
        shift
        ;;
    esac
  done

  # Resolve retention default from environment if not given on command line.
  if (( retention_days < 0 )); then
    retention_days="${RDEL_RETENTION_DAYS:-30}"
  fi
  if [[ ! "$retention_days" =~ '^[0-9]+$' ]]; then
    print -u2 -- "rdel: invalid retention value '$retention_days'"
    return 1
  fi

  # Dispatch subcommands.
  case "$subcommand" in
    list)
      if (( ${#sources} > 0 )); then
        print -u2 -- "rdel: --list does not take file arguments"
        return 1
      fi
      _rdel_gc "$trash_root" "$verbose"
      _rdel_list "$trash_root"
      return $?
      ;;
    restore)
      if (( ${#sources} > 0 )); then
        print -u2 -- "rdel: --restore does not take extra file arguments"
        return 1
      fi
      _rdel_restore "$trash_root" "$restore_id" "$force" "$verbose"
      return $?
      ;;
    empty)
      if (( ${#sources} > 0 )); then
        print -u2 -- "rdel: --empty does not take file arguments"
        return 1
      fi
      _rdel_empty "$trash_root" "$force" "$verbose"
      return $?
      ;;
  esac

  # Default behavior: move files to trash.
  if (( ${#sources} == 0 )); then
    _rdel_help >&2
    return 1
  fi

  if [[ ! -d "$trash_root" ]]; then
    command mkdir -p -- "$trash_root" || return 1
  fi

  _rdel_gc "$trash_root" "$verbose" || true

  local src abs_src basename id entry now expires
  local -i rc=0

  for src in "${sources[@]}"; do
    if [[ "$src" == "." || "$src" == ".." || "$src" == "/" || "$src" == "./" || "$src" == "../" || "$src" == ".//" || "$src" == "..//" ]]; then
      print -u2 -- "rdel: refusing to delete '$src'"
      rc=1
      continue
    fi

    # Strip a trailing slash for clean basename/absolute-path handling.
    if [[ "$src" != "/" ]]; then
      src="${src%/}"
    fi

    if [[ ! -e "$src" && ! -L "$src" ]]; then
      if (( ! force )); then
        print -u2 -- "rdel: cannot remove '$src': No such file or directory"
        rc=1
      fi
      continue
    fi

    abs_src="${src:a}"
    basename="$(command basename -- "$abs_src")"

    if [[ -z "$basename" || "$basename" == "/" || "$basename" == "." || "$basename" == ".." ]]; then
      print -u2 -- "rdel: refusing to delete '$src'"
      rc=1
      continue
    fi

    id="$(_rdel_generate_id "$trash_root")"
    entry="$trash_root/$id"
    command mkdir -p -- "$entry/payload" || { rc=1; continue; }

    if _rdel_move "$src" "$entry/payload/$basename"; then
      now="$(_rdel_now)"
      expires=$(( now + retention_days * 86400 ))
      _rdel_write_meta "$entry" "$id" "$abs_src" "$basename" "$now" "$expires"
      if (( verbose )); then
        print -- "rdel: moved '$src' to trash (expires in $(_rdel_human_duration $(( expires - now ))))"
      fi
    else
      rc=1
      command rm -rf -- "$entry" 2>/dev/null || true
    fi
  done

  return $rc
}

_rdel_help() {
  emulate -L zsh
  setopt localoptions no_shwordsplit
  command cat <<'EOF'
Usage: rdel [options] <file>...
       rdel --list
       rdel --restore <id>
       rdel --empty

Delayed-delete trash for zsh. Files are moved to a hidden trash bin and
permanently deleted after a retention period (default 30 days).

Options:
  -f, --force        Skip non-existent file warnings; skip --empty confirmation
  -v, --verbose      Print moved files and purged items
  -d, --days <n>     Retention window in days (default: RDEL_RETENTION_DAYS or 30)
  -r, -R, --recursive Accepted for rm compatibility (always recursive)
  -l, --list         List trashed files with IDs and time remaining
      --restore <id> Restore a trashed file to its original path
      --empty        Permanently delete all trashed items now
  -h, --help         Show this help

Environment:
  RDEL_TRASH         Trash directory (default: ~/.local/share/rdel/.trash)
  RDEL_RETENTION_DAYS Default retention in days (default: 30)
EOF
}

_rdel_gc() {
  emulate -L zsh
  setopt localoptions no_shwordsplit
  local root="$1"
  local verbose="$2"
  [[ -d "$root" ]] || return 0

  local now="$(_rdel_now)"
  local entry expires_at id original
  local -a entries
  entries=("${(f)$(command find "$root" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)}")

  for entry in "${entries[@]}"; do
    [[ -z "$entry" ]] && continue
    _rdel_meta_get "$entry" expires_at
    expires_at="$REPLY"
    [[ -z "$expires_at" ]] && continue

    if (( now > expires_at )); then
      _rdel_meta_get "$entry" id
      id="$REPLY"
      _rdel_meta_get "$entry" original
      original="$REPLY"
      if [[ -n "$verbose" && "$verbose" -ne 0 ]]; then
        print -- "rdel: purging '${original:-$entry}' (${id:-$entry})"
      fi
      command rm -rf -- "$entry"
    fi
  done
}

_rdel_list() {
  emulate -L zsh
  setopt localoptions no_shwordsplit
  local root="$1"
  if [[ ! -d "$root" ]] || [[ -z "$(command find "$root" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)" ]]; then
    print -- "Trash is empty."
    return 0
  fi

  local entry id original expires_at remaining
  local -a entries
  entries=("${(f)$(command find "$root" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | command sort)}")

  printf '%-30s %-50s %s\n' "ID" "ORIGINAL" "EXPIRES IN"

  for entry in "${entries[@]}"; do
    [[ -z "$entry" ]] && continue
    _rdel_meta_get "$entry" id
    id="$REPLY"
    _rdel_meta_get "$entry" original
    original="$REPLY"
    _rdel_meta_get "$entry" expires_at
    expires_at="$REPLY"

    if [[ -n "$expires_at" ]]; then
      remaining=$(( expires_at - $(_rdel_now) ))
      if (( remaining < 0 )); then remaining=0; fi
      remaining="$(_rdel_human_duration "$remaining")"
    else
      remaining="unknown"
    fi

    if [[ -z "$id" ]]; then
      id="$(command basename -- "$entry")"
    fi
    if [[ -z "$original" ]]; then
      original="$entry"
    fi

    printf '%-30s %-50s %s\n' "$id" "$original" "$remaining"
  done
}

_rdel_restore() {
  emulate -L zsh
  setopt localoptions no_shwordsplit
  local root="$1"
  local id="$2"
  local force="$3"
  local verbose="$4"

  local entry="$root/$id"
  if [[ ! -d "$entry" ]]; then
    print -u2 -- "rdel: no trashed item with id '$id'"
    return 1
  fi

  local original basename source parent
  _rdel_meta_get "$entry" original
  original="$REPLY"
  _rdel_meta_get "$entry" basename
  basename="$REPLY"

  if [[ -z "$original" || -z "$basename" ]]; then
    print -u2 -- "rdel: corrupt metadata for '$id'"
    return 1
  fi

  source="$entry/payload/$basename"
  if [[ ! -e "$source" && ! -L "$source" ]]; then
    print -u2 -- "rdel: trashed payload missing for '$id'"
    return 1
  fi

  parent="$(command dirname -- "$original")"
  command mkdir -p -- "$parent"

  if [[ -e "$original" || -L "$original" ]]; then
    if [[ -z "$force" || "$force" -eq 0 ]]; then
      print -u2 -- "rdel: restore target already exists '$original' (use -f to overwrite)"
      return 1
    fi
    command rm -rf -- "$original"
  fi

  if _rdel_move "$source" "$original"; then
    command rm -rf -- "$entry"
    if [[ -n "$verbose" && "$verbose" -ne 0 ]]; then
      print -- "rdel: restored '$original'"
    fi
    return 0
  else
    print -u2 -- "rdel: failed to restore '$original'"
    return 1
  fi
}

_rdel_empty() {
  emulate -L zsh
  setopt localoptions no_shwordsplit
  local root="$1"
  local force="$2"
  local verbose="$3"

  if [[ ! -d "$root" ]]; then
    print -- "Trash is empty."
    return 0
  fi

  local -a entries
  entries=("${(f)$(command find "$root" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)}")

  # Count non-empty entries.
  local count=0
  local e
  for e in "${entries[@]}"; do
    [[ -n "$e" ]] && (( count++ ))
  done

  if (( count == 0 )); then
    print -- "Trash is empty."
    return 0
  fi

  if [[ -z "$force" || "$force" -eq 0 ]]; then
    local ans
    printf -- 'Permanently delete %s trashed item(s)? [y/N] ' "$count"
    command read -r ans
    if [[ "$ans" != [yY]* ]]; then
      print -- "Cancelled."
      return 0
    fi
  fi

  local entry original
  for entry in "${entries[@]}"; do
    [[ -z "$entry" ]] && continue
    if [[ -n "$verbose" && "$verbose" -ne 0 ]]; then
      _rdel_meta_get "$entry" original
      original="$REPLY"
      print -- "rdel: emptying '${original:-$entry}'"
    fi
    command rm -rf -- "$entry"
  done

  print -- "Trash emptied."
}

_rdel_move() {
  emulate -L zsh
  setopt localoptions no_shwordsplit
  local src="$1"
  local target="$2"

  # Fast path: same-filesystem rename.
  if command mv -f -- "$src" "$target"; then
    return 0
  fi

  # Cross-filesystem / cross-device fallback: copy then remove.
  local parent
  parent="$(command dirname -- "$target")"
  command mkdir -p -- "$parent"

  if [[ -L "$src" ]]; then
    if command cp -P -p -f -R -- "$src" "$target"; then
      command rm -rf -- "$src"
      return 0
    fi
  elif [[ -d "$src" ]]; then
    if command cp -R -p -f -- "$src" "$target"; then
      command rm -rf -- "$src"
      return 0
    fi
  else
    if command cp -p -f -- "$src" "$target"; then
      command rm -f -- "$src"
      return 0
    fi
  fi

  return 1
}

_rdel_write_meta() {
  emulate -L zsh
  setopt localoptions no_shwordsplit
  local entry="$1"
  local id="$2"
  local original="$3"
  local basename="$4"
  local deleted_at="$5"
  local expires_at="$6"

  {
    print -- "id: $id"
    print -- "original: $original"
    print -- "basename: $basename"
    print -- "deleted_at: $deleted_at"
    print -- "expires_at: $expires_at"
  } > "$entry/meta"
}

_rdel_meta_get() {
  emulate -L zsh
  setopt localoptions no_shwordsplit
  local entry="$1"
  local key="$2"
  REPLY=$(command sed -n "s/^${key}: //p" "$entry/meta" 2>/dev/null)
}

_rdel_generate_id() {
  emulate -L zsh
  setopt localoptions no_shwordsplit
  local root="$1"
  local id rand
  while true; do
    rand=$(command od -An -tx1 -N4 /dev/urandom 2>/dev/null | command tr -d ' \n')
    if [[ -z "$rand" ]]; then
      rand="$(command date +%s)-$$"
    fi
    id="$(command date +'%Y%m%d-%H%M%S')-${rand}"
    [[ ! -e "$root/$id" ]] && break
  done
  print -- "$id"
}

_rdel_now() {
  command date +%s
}

_rdel_human_duration() {
  emulate -L zsh
  setopt localoptions no_shwordsplit
  local -i secs="$1"
  if (( secs < 0 )); then secs=0; fi
  local -i days=$(( secs / 86400 ))
  secs=$(( secs % 86400 ))
  local -i hours=$(( secs / 3600 ))
  secs=$(( secs % 3600 ))
  local -i mins=$(( secs / 60 ))
  secs=$(( secs % 60 ))

  if (( days > 0 )); then
    print -- "${days}d ${hours}h"
  elif (( hours > 0 )); then
    print -- "${hours}h ${mins}m"
  elif (( mins > 0 )); then
    print -- "${mins}m ${secs}s"
  else
    print -- "${secs}s"
  fi
}

unalias rdel 2>/dev/null || true
