# Sourced by the harness; captures the nested compositor's output with grim.
#
# grim speaks wlr-screencopy to the compositor its WAYLAND_DISPLAY names,
# so the one thing that keeps a capture off the live desktop is the socket
# handed to it. shot_socket resolves the nested socket and refuses the
# caller's own runtime dir, where the live session's sockets are, anything
# outside the sandbox's runtime dir, and anything that is not a socket.
# shot_dir_under refuses an output directory outside the repository's tmp/.
#
# A capture is proved current, not a frame the nested compositor drew
# before the change: `shot` compares each capture with the previous shot's,
# and a shot taken after a visible change must differ from it. It captures
# until two captures in a row match (a settled frame), and takes the last
# capture that differs once SHOT_SETTLE_S passes without one (an animated
# frame, such as an orbiting edge light: a compositor still drawing it is
# live). A capture that never differs from the previous shot is a stale
# frame and fails, as does a grim that does not return within
# SHOT_GRIM_TIMEOUT_S.
#
# A shot captures the one output SHOT_OUTPUT names, not the whole layout:
# grim captures a layout one output at a time and fails the whole capture
# with `failed to create buffer` on an output with no size, as a headless
# output of the nested compositor is on an NVIDIA host.
#
# Every shot is one line in shots.tsv beside the images: name, sha256 of
# the file, the previous shot's name, `settled` or `animated`, and the shot
# chrome state: the word SHOT_CHROME_READER prints when it reads the same
# before the first capture and after the last, `changed` when it does not,
# `-` when no reader is set. With SHOT_CHROME_REQUIRE set, a shot whose
# state is another word is refused after its capture, its PNG removed and
# no line written, so every line of shots.tsv was taken in that state.

shot_refuse() { # REASON VALUE
  printf 'shot: refused: reason=%s value=%s\n' "$1" "$2" >&2
  return 1
}

# shot_socket RUNTIME_DIR NAME: the nested socket's absolute path,
# RUNTIME_DIR/NAME, which must not lie in XDG_RUNTIME_DIR itself.
shot_socket() {
  local rt="$1" name="$2" rt_real path
  [[ -n $name && $name != */* && $name != . && $name != .. ]] || { shot_refuse socket-not-a-name "$name"; return 1; }
  [[ -d $rt ]] || { shot_refuse runtime-dir-missing "$rt"; return 1; }
  [[ -n ${XDG_RUNTIME_DIR:-} ]] || { shot_refuse caller-runtime-dir-unnamed "$rt"; return 1; }
  rt_real="$(readlink -f -- "$rt")"
  [[ $rt_real != "$(readlink -f -- "$XDG_RUNTIME_DIR")" ]] || { shot_refuse caller-runtime-dir "$rt_real"; return 1; }
  path="$(readlink -f -- "$rt/$name")" || { shot_refuse socket-unresolved "$rt/$name"; return 1; }
  [[ -S $path ]] || { shot_refuse not-a-socket "$path"; return 1; }
  [[ $path == "$rt_real/$name" ]] || { shot_refuse outside-runtime-dir "$path"; return 1; }
  printf '%s\n' "$path"
}

# shot_dir_under REPO DIR: DIR made and printed as an absolute path, which
# must lie under REPO/tmp/.
shot_dir_under() {
  local root dir
  root="$(readlink -f -- "$1")/tmp"
  mkdir -p -- "$2" || { shot_refuse out-dir-unwritable "$2"; return 1; }
  dir="$(readlink -f -- "$2")"
  [[ $dir == "$root"/* ]] || { shot_refuse out-dir-outside-tmp "$dir"; return 1; }
  printf '%s\n' "$dir"
}

# shot_grim SOCKET RUNTIME_DIR ARGS...: grim with ARGS, alone in an empty
# environment beside SOCKET, which shot_socket gave, within
# SHOT_GRIM_TIMEOUT_S; the status is timeout's, 124 when grim timed out.
shot_grim() {
  timeout "${SHOT_GRIM_TIMEOUT_S:-10}" env -i PATH="$PATH" XDG_RUNTIME_DIR="$2" WAYLAND_DISPLAY="${1##*/}" grim "${@:3}"
}

# shot_pixel SOCKET RUNTIME_DIR X Y: the colour at layout position (X, Y)
# as rrggbb, one layout pixel grim captures at scale 1 as a binary PPM.
# The output scale must not enlarge that one-pixel sample. A capture that fails,
# times out or is no 1 by 1 PPM prints `pixel=unreadable` and returns 1.
shot_pixel() {
  local out
  out="$(shot_grim "$1" "$2" -s 1 -g "$3,$4 1x1" -t ppm - 2>/dev/null | python3 -c '
import sys
data = sys.stdin.buffer.read()
head = data.split(b"\n", 3)
if len(head) == 4 and head[:3] == [b"P6", b"1 1", b"255"] and len(head[3]) == 3:
    print(head[3].hex())
')" && [[ $out =~ ^[0-9a-f]{6}$ ]] || { echo "pixel=unreadable"; return 1; }
  printf '%s\n' "$out"
}

shot_last_name=""
shot_last_hash=""

# shot_grab SOCKET RUNTIME_DIR OUTPUT FILE: one capture of OUTPUT, grim
# alone in an empty environment beside the nested socket; the status is
# shot_grim's.
shot_grab() {
  shot_grim "$1" "$2" -o "$3" -t png "$4" >/dev/null 2>>"${4%/*}/grim.log"
}

# shot_chrome: the shot's chrome state from SHOT_CHROME_READER, a command
# the caller sets; `-` when it is unset. A reader that fails keeps the word
# it printed.
shot_chrome() {
  [[ -n ${SHOT_CHROME_READER:-} ]] || { echo -; return; }
  $SHOT_CHROME_READER || true
}

# shot NAME: SHOT_DIR/NAME.png, proved current against the previous shot.
# Needs SHOT_DIR, SHOT_SOCKET, SHOT_RUNTIME_DIR and SHOT_OUTPUT. Returns 1
# for a stale or failed capture or one refused for its chrome state; prints
# what it wrote.
shot() {
  local name="$1" file part hash stable="" last="" kind="" deadline status chrome_before chrome_after chrome
  [[ $name =~ ^[A-Za-z0-9._-]+$ ]] || { shot_refuse name "$name"; return 1; }
  [[ -n ${SHOT_OUTPUT:-} ]] || { shot_refuse output-unnamed "$name"; return 1; }
  chrome_before="$(shot_chrome)"
  file="$SHOT_DIR/$name.png"
  part="$SHOT_DIR/.$name.part.png"
  deadline=$(( $(date +%s%N) / 1000000 + ${SHOT_SETTLE_S:-5} * 1000 ))
  while :; do
    status=0
    shot_grab "$SHOT_SOCKET" "$SHOT_RUNTIME_DIR" "$SHOT_OUTPUT" "$part" || status=$?
    if [[ $status -ne 0 ]]; then
      rm -f -- "$part"
      printf 'shot: capture-failed name=%s grim-status=%s\n' "$name" "$([[ $status -eq 124 ]] && echo timeout || echo error)" >&2
      return 1
    fi
    hash="$(sha256sum -- "$part" | cut -d' ' -f1)"
    if [[ $hash != "$shot_last_hash" ]]; then
      if [[ $hash == "$last" ]]; then kind=settled; stable="$hash"; break; fi
      last="$hash"
      mv -f -- "$part" "$file"
    fi
    if (( $(date +%s%N) / 1000000 >= deadline )); then
      [[ -n $last ]] && { kind=animated; break; }
      rm -f -- "$part"
      printf 'shot: stale name=%s previous=%s sha256=%s\n' "$name" "$shot_last_name" "$hash" >&2
      echo "every capture for ${SHOT_SETTLE_S:-5} s matched the previous shot, so the nested compositor did not draw the change" >&2
      return 1
    fi
    sleep 0.25
  done
  [[ $kind == settled ]] && mv -f -- "$part" "$file"
  rm -f -- "$part"
  chrome_after="$(shot_chrome)"
  chrome="$chrome_before"
  [[ $chrome_after == "$chrome_before" ]] || chrome=changed
  if [[ -n ${SHOT_CHROME_REQUIRE:-} && $chrome != "$SHOT_CHROME_REQUIRE" ]]; then
    rm -f -- "${file:?}"
    shot_refuse chrome "$chrome" || true
    printf 'the shot %s needs chrome %s\n' "$name" "$SHOT_CHROME_REQUIRE" >&2
    return 1
  fi
  printf '%s\t%s\t%s\t%s\t%s\n' "$name" "${stable:-$last}" "${shot_last_name:--}" "$kind" "$chrome" >>"$SHOT_DIR/shots.tsv"
  shot_last_name="$name"
  shot_last_hash="${stable:-$last}"
  printf '  shot  %s (%s, chrome %s)\n' "$file" "$kind" "$chrome"
}
