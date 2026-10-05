#!/usr/bin/env bash
# The web apps' file and network steps. The service runs it with bash from
# the plugin's published source revision, one verb a run, each run one
# child of the service's one Process, which waits for it.
#
#   files.sh page <url>                   the page at URL on stdout, at most
#                                         1 MiB
#   files.sh icon <base> <source>...      the first source that is an image,
#                                         saved as <base>.<png|jpg|gif|ico|
#                                         webp|svg>, printed as
#                                         <index>\t<path>, 0 the first source
#   files.sh read <icons dir>             each saved record, one line each:
#                                         record\t<name>\t<json>, then each
#                                         file name in the directory:
#                                         file\t<file name>
#   files.sh apply <applications dir> <icons dir> [<name> <entry> <record>]...
#                                         each listed app's desktop entry
#                                         and record written, and every
#                                         vgs-webapp-*.desktop entry, icon
#                                         and record of an app not listed
#                                         removed
#
# A source is an http or https address, read with curl, or an absolute
# path, read as a file. Each read is bounded: 10 s and 1 MiB for an address,
# 1 MiB for a file. An image is known by its first bytes, never by its name
# or the server's word for it. A file is written beside its target and
# renamed over it, so a reader never sees half of one.
#
# Every refusal is one keyed line on stderr:
#   exit 2  webapps: refused: usage
#   exit 3  webapps: page=failed url=<url>
#   exit 4  webapps: icon=none base=<base>
#   exit 5  webapps: name=<name> invalid
#   exit 6  webapps: write=failed path=<path>
set -euo pipefail
export LC_ALL=C

max_bytes=1048576
entry_prefix=vgs-webapp-

usage() { echo "webapps: refused: usage" >&2; exit 2; }

fetch() { # SOURCE OUT
  if [[ $1 == /* ]]; then
    [[ -f $1 && -r $1 ]] || return 1
    (( $(stat -c %s -- "$1") <= max_bytes )) || return 1
    cp -- "$1" "$2"
    return
  fi
  curl --fail --silent --location --proto '=http,https' --proto-redir '=http,https' \
    --max-time 10 --max-filesize "$max_bytes" --max-redirs 5 \
    --user-agent 'Mozilla/5.0 (X11; Linux x86_64) VGS' --output "$2" -- "$1" || return 1
  (( $(stat -c %s -- "$2") <= max_bytes ))
}

# The extension the image in FILE takes, from its first bytes, or nothing.
image_type() { # FILE
  local head
  head="$(od -An -tx1 -N12 -- "$1" | tr -d ' \n')" || return 1
  case "$head" in
    89504e470d0a1a0a*) echo png ;;
    ffd8ff*) echo jpg ;;
    474946383?61*) echo gif ;;
    00000100*) echo ico ;;
    52494646????????57454250) echo webp ;;
    *)
      if head -c 4096 -- "$1" | tr -d '\0' | grep -qiE '<svg[[:space:]>]'; then echo svg; fi
      ;;
  esac
}

page() { # URL
  local tmp status=0
  tmp="$(mktemp)" || exit 3
  fetch "$1" "$tmp" || status=$?
  if [[ $status -ne 0 ]]; then
    rm -f -- "$tmp"
    echo "webapps: page=failed url=$1" >&2
    exit 3
  fi
  cat -- "$tmp"
  rm -f -- "$tmp"
}

icon() { # BASE SOURCE...
  local base="$1" part type index=0 ext
  shift
  mkdir -p -- "$(dirname -- "$base")"
  part="$(mktemp "$base.XXXXXX.part")" || exit 4
  for source in "$@"; do
    if fetch "$source" "$part" && type="$(image_type "$part")" && [[ -n $type ]]; then
      mv -f -- "$part" "$base.$type"
      for ext in png jpg gif ico webp svg; do
        [[ $ext == "$type" ]] || rm -f -- "$base.$ext"
      done
      printf '%s\t%s\n' "$index" "$base.$type"
      return
    fi
    index=$((index + 1))
  done
  rm -f -- "$part"
  echo "webapps: icon=none base=$base" >&2
  exit 4
}

read_records() { # ICONS_DIR
  local file name
  [[ -d $1 ]] || return 0
  for file in "$1"/*.json; do
    [[ -f $file ]] || continue
    name="$(basename -- "$file" .json)"
    printf 'record\t%s\t%s\n' "$name" "$(tr -d '\n' <"$file")"
  done
  for file in "$1"/*; do
    [[ -f $file ]] && printf 'file\t%s\n' "$(basename -- "$file")"
  done
  return 0
}

# write TEXT to PATH through a file beside it, only when it differs.
write() { # PATH TEXT
  local tmp
  if [[ -f $1 ]] && [[ "$(cat -- "$1"; printf x)" == "$2x" ]]; then return; fi
  tmp="$(mktemp "$1.XXXXXX")" || { echo "webapps: write=failed path=$1" >&2; exit 6; }
  if ! printf '%s' "$2" >"$tmp" || ! mv -f -- "$tmp" "$1"; then
    rm -f -- "$tmp"
    echo "webapps: write=failed path=$1" >&2
    exit 6
  fi
}

apply() { # APPS_DIR ICONS_DIR [NAME ENTRY RECORD]...
  local apps_dir="$1" icons_dir="$2" file name keep=" "
  shift 2
  (( $# % 3 == 0 )) || usage
  mkdir -p -- "$apps_dir" "$icons_dir"
  while (( $# > 0 )); do
    [[ $1 =~ ^[a-z0-9-]+$ ]] || { echo "webapps: name=$1 invalid" >&2; exit 5; }
    write "$apps_dir/$entry_prefix$1.desktop" "$2"
    write "$icons_dir/$1.json" "$3"
    keep+="$1 "
    shift 3
  done
  for file in "$apps_dir/$entry_prefix"*.desktop; do
    [[ -e $file ]] || continue
    name="$(basename -- "$file" .desktop)"
    name="${name#"$entry_prefix"}"
    if [[ $keep != *" $name "* ]]; then rm -f -- "$file"; fi
  done
  for file in "$icons_dir"/*; do
    [[ -e $file ]] || continue
    name="$(basename -- "$file")"
    # A .part file is a read cut short: the service runs one step at a
    # time, so none is being written now.
    if [[ $name == *.part || $keep != *" ${name%%.*} "* ]]; then rm -f -- "$file"; fi
  done
}

case "${1:-}" in
  page) [[ $# -eq 2 ]] || usage; page "$2" ;;
  icon) [[ $# -ge 3 ]] || usage; shift; icon "$@" ;;
  read) [[ $# -eq 2 ]] || usage; read_records "$2" ;;
  apply) [[ $# -ge 3 ]] || usage; shift; apply "$@" ;;
  *) usage ;;
esac
