# shellcheck shell=bash
# bin/lib/ipc-reply.sh: classifies the last stdout line from
# `qs ipc call` and reassembles a paged reply. Source this file from Bash.
# Loading it defines two arrays and five functions, prints nothing, starts
# no process and leaves the caller's shell options alone. The table rests
# on Quickshell 0.3.1 `src/io/ipccomm.cpp` callFunction and
# `src/ipc/ipc.hpp` waitForResponse; the page protocol is
# `shell/Core/IpcPages.qml`'s.
#
#   vgs_ipc_last_line_into TEXT
#     sets vgs_ipc_last_line to the text after TEXT's last newline, TEXT
#     itself when it holds none: qs can print log lines ahead of a reply.
#   vgs_ipc_strip_into LINE
#     sets vgs_ipc_stripped to LINE with SGR colour escapes removed.
#   vgs_ipc_reply_failure LINE
#     prints a stable reason key and returns 0 when LINE is a Quickshell IPC
#     client failure. It returns 1 for a normal reply and for an empty line.
#     A table row of unknown kind prints `ipc-reply: kind=<kind> row=<reason>`
#     on stderr and returns 2.
#   vgs_ipc_paged_id TARGET LINE
#     returns 0 with vgs_ipc_paged set to the reply id when LINE is
#     `paged=<id>` from a target in vgs_ipc_paging_targets, the targets
#     whose replies answer through the pager; 1 for any other reply, which
#     is whole.
#   vgs_ipc_pages FETCH ID
#     reassembles the reply `paged=ID`. For each page from 0 it runs
#     `FETCH ID INDEX` in this shell, which sets vgs_ipc_page to the
#     page's reply line, `<pages> <slice>`, or returns non-zero after its
#     own diagnostic. Returns 0 with the whole document in
#     vgs_ipc_document. Returns 1 with vgs_ipc_page_failure set to
#     `<reason> page=<index>` and vgs_ipc_page to the line read, reason
#     `absent` (the shell no longer keeps the reply), `refused` (an index
#     out of range), `bad-header`, `bad-count` or `count-changed`; returns
#     2 with `fetch page=<index> status=<n>` when FETCH failed.

# shell.qml's `shell` handler and the smoke probe's `smoke` handler.
vgs_ipc_paging_targets=(shell smoke)

vgs_ipc_failure_rows=(
  'client-error|contains|ERROR quickshell.ipc'
  'function-not-found|exact|Function not found.'
  'target-not-found|exact|Target not found.'
  'not-ready|exact|Not ready to accept queries yet.'
  'target-required|exact|Target required to send message.'
  'function-required|exact|Function required to send message.'
  'too-many-arguments|prefix|Too many arguments provided'
  'too-few-arguments|prefix|Too few arguments provided'
  'unparseable-argument|prefix|Unable to parse argument'
  'arguments|prefix|Function definition:'
)

# Pure Bash, so it forks nothing and cannot fail. A one-line reply, the
# common one, is returned after one scan for a newline. `${TEXT##*$'\n'}`
# says the same and is not used: bash matches that pattern against every
# prefix, which took 0.19 s for one 32 KiB reply and grows with the square
# (bash 5.3.20, host cachy, 2026-10-04).
vgs_ipc_last_line_into() { # TEXT
  local head
  if [[ $1 != *$'\n'* ]]; then
    vgs_ipc_last_line="$1"
    return 0
  fi
  head="${1%$'\n'*}"
  vgs_ipc_last_line="${1:${#head}+1}"
}

# Pure Bash, so the strip forks nothing and cannot fail.
vgs_ipc_strip_into() { # LINE
  vgs_ipc_stripped="$1"
  while [[ $vgs_ipc_stripped =~ ^(.*)$'\e'\[[0-9\;]*m(.*)$ ]]; do
    vgs_ipc_stripped="${BASH_REMATCH[1]}${BASH_REMATCH[2]}"
  done
}

vgs_ipc_reply_failure() { # LINE
  local stripped row reason rest kind text
  vgs_ipc_strip_into "$1"
  stripped="$vgs_ipc_stripped"
  for row in "${vgs_ipc_failure_rows[@]}"; do
    reason="${row%%|*}"
    rest="${row#*|}"
    kind="${rest%%|*}"
    text="${rest#*|}"
    case "$kind" in
      contains) [[ $stripped == *"$text"* ]] || continue ;;
      exact) [[ $stripped == "$text" ]] || continue ;;
      prefix) [[ $stripped == "$text"* ]] || continue ;;
      *)
        printf 'ipc-reply: kind=%s row=%s\n' "$kind" "$reason" >&2
        return 2
        ;;
    esac
    printf '%s\n' "$reason"
    return 0
  done
  return 1
}

vgs_ipc_paged_id() { # TARGET LINE
  local target
  vgs_ipc_paged=""
  [[ $2 =~ ^paged=([0-9]+)$ ]] || return 1
  for target in "${vgs_ipc_paging_targets[@]}"; do
    if [[ $1 == "$target" ]]; then
      vgs_ipc_paged="${BASH_REMATCH[1]}"
      return 0
    fi
  done
  return 1
}

vgs_ipc_pages() { # FETCH ID
  local fetch="$1" id="$2" index=0 pages="" count slice status
  vgs_ipc_document=""
  vgs_ipc_page_failure=""
  while :; do
    vgs_ipc_page=""
    status=0
    "$fetch" "$id" "$index" || status=$?
    if ((status)); then
      vgs_ipc_page_failure="fetch page=$index status=$status"
      return 2
    fi
    if [[ $vgs_ipc_page == absent ]]; then
      vgs_ipc_page_failure="absent page=$index"
      return 1
    fi
    if [[ $vgs_ipc_page == "refused: "* ]]; then
      vgs_ipc_page_failure="refused page=$index"
      return 1
    fi
    if [[ ! $vgs_ipc_page =~ ^([0-9]+)\ (.*)$ ]]; then
      vgs_ipc_page_failure="bad-header page=$index"
      return 1
    fi
    count="${BASH_REMATCH[1]}"
    slice="${BASH_REMATCH[2]}"
    if [[ -z $pages ]]; then
      if [[ ! $count =~ ^[1-9][0-9]*$ ]]; then
        vgs_ipc_page_failure="bad-count page=$index"
        return 1
      fi
      pages="$count"
    elif [[ $count != "$pages" ]]; then
      vgs_ipc_page_failure="count-changed page=$index"
      return 1
    fi
    vgs_ipc_document+="$slice"
    index=$((index + 1))
    ((index < pages)) || return 0
  done
}
