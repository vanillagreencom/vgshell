#!/usr/bin/env bash
# Pins scripts/smoke/sink/sink.c, the compositor the nested Hyprland draws
# to. The sink and its client, scripts/fixtures/sink/probe.c, are built
# with build_helper taken from scripts/smoke/harness.sh, as the harness
# builds the sink. The suite runs inside scripts/smoke/gpu-fence.sh, since
# the sink reads its formats through EGL on the render node it names. Each
# run starts one sink on a private runtime dir, with the fence's first
# render node as its main device, and runs the probe against it with two
# toplevels, 30 frames and 50 pairs of file descriptors; no display is
# needed. A run holds when the sink:
# - lists exactly the five globals at the versions aquamarine 0.15.1 binds
#   (globals);
# - states a pointer and a keyboard and sends no input event (input);
# - names the render node's number as the main device and a format table
#   of the four formats it offers, each entry with an explicit modifier
#   (feedback); which modifiers EGL renders to is EGL's, not checked here;
# - configures each toplevel once, at 1920x1080 (configure);
# - pings after the first buffer commit (ping);
# - releases every committed buffer, the last ones included (release);
# - paces frame callbacks no faster than its 60 Hz clock (pacing): 30 callbacks
#   take at least 28 periods, a floor no load can break;
# - holds the same open file descriptors after the probe left as before
#   it came (fds).
# It also refuses a relative socket and a main device that is no
# character device with exit 2, and a character device that is no render
# node with exit 1.
#
# The controls at the end build a copy of the sink with one defect each
# and require the rule it breaks to go red.
#
# Every process runs without WAYLAND_DISPLAY, DISPLAY and
# HYPRLAND_INSTANCE_SIGNATURE, and the probe only with the sink's own
# socket; the suite signals only the sinks it started. A missing build
# package exits 77 through build_helper, and a fence with no render node as
# `missing=render-node`; a sink or probe that does not compile fails.
#
# Exit 0 when every case and control holds, 1 otherwise.
set -euo pipefail
unset WAYLAND_DISPLAY WAYLAND_SOCKET DISPLAY HYPRLAND_INSTANCE_SIGNATURE

self="$(readlink -f -- "${BASH_SOURCE[0]}")"
repo="$(cd -- "$(dirname -- "$self")/.." && pwd)"
"$repo/scripts/smoke/gpu-fence.sh" --check || exec "$repo/scripts/smoke/gpu-fence.sh" "$self" "$@"

tmp="$(mktemp -d)" || { echo "test-smoke-sink: scratch=mktemp-failed" >&2; exit 1; }
[[ -d $tmp && ! -L $tmp ]] || { echo "test-smoke-sink: scratch=not-a-directory value=[$tmp]" >&2; exit 1; }
tmp="$(cd -- "$tmp" && pwd -P)" || { echo "test-smoke-sink: scratch=resolve-failed" >&2; exit 1; }
# Only a sink still running is signalled, so no reaped pid is a target.
trap 'for pid in $(jobs -pr); do kill -KILL "$pid" 2>/dev/null || true; done; rm -rf -- "${tmp:?}"' EXIT

failures=0
ok() { printf '  ok    %s\n' "$*"; }
fail() { failures=$((failures + 1)); printf '  FAIL  %s\n' "$*"; }

if ! build_text="$(sed -n '/^build_helper() {/,/^}/p' "$repo/scripts/smoke/harness.sh")" || [[ $build_text != "build_helper() {"*$'\n}' ]]; then
  echo "test-smoke-sink: extract=failed function=build_helper" >&2
  exit 1
fi
eval "$build_text"
if ! wayland_protocols="$(pkg-config --variable=pkgdatadir wayland-protocols)" || [[ -z $wayland_protocols ]]; then
  printf 'test-smoke-sink: status=not-measured missing=wayland-protocols\n'
  exit 77
fi
xdg_xml="$repo/scripts/smoke/toplevel/xdg-shell.xml"
dmabuf_xml="$wayland_protocols/stable/linux-dmabuf/linux-dmabuf-v1.xml"
sandbox="$tmp/build"
mkdir -- "$sandbox"
# built LABEL NAME KEY SOURCE ARGS...: build_helper in a subshell. A
# missing package ends a suite that has failed nothing as not measured; a
# compile error, or a missing package once a check has failed, fails LABEL
# and returns 1, so a sink.c or probe.c that does not compile goes red and
# no FAIL already printed turns into 77.
built() {
  local label="$1" out status=0
  shift
  out="$(build_helper "$@")" || status=$?
  [[ $status != 0 ]] || return 0
  if [[ $out != *-helper-build* && $failures -eq 0 ]]; then
    printf '%s\n' "$out"
    exit 77
  fi
  fail "$label: $(head -n 4 <<<"$out")"
  return 1
}
if ! built "the probe compiles" probe probe "$repo/scripts/fixtures/sink/probe.c" "$xdg_xml" "$dmabuf_xml"; then
  echo "test-smoke-sink: failed=$failures"
  exit 1
fi
probe="$sandbox/probe"
render_node=""
for candidate in /dev/dri/renderD*; do
  [[ -c $candidate ]] && { render_node="$candidate"; break; }
done
if [[ -z $render_node ]]; then
  printf 'test-smoke-sink: status=not-measured missing=render-node\n'
  exit 77
fi

# build_sink LABEL DIR SOURCE: DIR/sink built from SOURCE, through built.
build_sink() {
  mkdir -p -- "$1"
  local sandbox="$1"
  built "$3" sink sink "$2" "$xdg_xml" "$dmabuf_xml" wayland-server egl gbm libdrm
}

fd_count() { local fds=("/proc/$1/fd"/*); echo "${#fds[@]}"; }

# run_sink SINK DIR: SINK on an owned private runtime socket with the render node as its
# main device, the probe run against it, and the probe's lines in DIR/probe.out
# with `fds-before N` and `fds-after N` appended. Returns 1 when the sink
# never listens.
run_sink() {
  local sink="$1" dir="$2" pid socket status=0
  sink_runtime="$(mktemp -d "$XDG_RUNTIME_DIR/owned/sink.XXXXXX")" || return 1
  socket="$sink_runtime/vgs-sink"
  XDG_RUNTIME_DIR="$sink_runtime" "$sink" "$socket" "$render_node" 2>"$dir/sink.err" &
  pid=$!
  for _ in $(seq 1 100); do
    [[ ! -S $socket ]] || break
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.05
  done
  if [[ ! -S $socket ]]; then
    kill -KILL "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    return 1
  fi
  printf 'fds-before %s\n' "$(fd_count "$pid")" >"$dir/fds"
  timeout -k 2 20 env -i PATH="$PATH" WAYLAND_DISPLAY="$socket" "$probe" 2 30 50 >"$dir/probe.out" 2>&1 || status=$?
  printf 'probe-exit %s\n' "$status" >>"$dir/probe.out"
  # The sink drops the client once it reads the hang-up; it then holds no
  # file descriptor of the probe's.
  for _ in $(seq 1 50); do
    [[ $(fd_count "$pid") -gt $(cut -d' ' -f2 "$dir/fds") ]] || break
    sleep 0.05
  done
  printf 'fds-after %s\n' "$(fd_count "$pid")" >>"$dir/fds"
  cat -- "$dir/fds" >>"$dir/probe.out"
  kill -TERM "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
}

node_device="$(stat -L -c '%Hr:%Lr' -- "$render_node")"
want_globals=$'global wl_compositor 6\nglobal wl_seat 9\nglobal wl_shm 1\nglobal xdg_wm_base 6\nglobal zwp_linux_dmabuf_v1 4'

# broken_rules OUT: the name of each rule the probe's lines in OUT break,
# one a line, none for a run that holds every rule.
broken_rules() {
  local out="$1" lines frames_ms
  lines="$(<"$out")"
  grep -qx 'probe-exit 0' <<<"$lines" && grep -qx done <<<"$lines" || echo probe
  [[ $(grep '^global ' <<<"$lines" | sort) == "$want_globals" ]] || echo globals
  grep -qx 'capabilities 3' <<<"$lines" && ! grep -q '^input ' <<<"$lines" || echo input
  # XR24, AR24, XB24 and AB24 in hex, each with a modifier other than
  # DRM_FORMAT_MOD_INVALID.
  grep -qx "main-device $node_device" <<<"$lines" && grep -q '^format ' <<<"$lines" \
    && ! grep -v -q -E '^format (34325258|34325241|34324258|34324241) [0-9a-f]{16}$' <<<"$(grep '^format ' <<<"$lines")" \
    && ! grep -q '^format [0-9a-f]* 00ffffffffffffff$' <<<"$lines" || echo feedback
  [[ $(grep '^configure ' <<<"$lines") == $'configure 0 1920x1080\nconfigure 1 1920x1080' ]] || echo configure
  grep -qx 'ping committed=1' <<<"$lines" || echo ping
  # Two mapping commits and the 30 framed ones.
  [[ $(grep -c '^release ' <<<"$lines") == 32 ]] || echo release
  # Each callback takes its own expiry of the 60 Hz clock, the first one
  # possibly one that expired just before the first framed commit: 28
  # periods, floored to whole milliseconds.
  frames_ms="$(sed -n 's/^frames 30 ms=\([0-9]*\)$/\1/p' <<<"$lines")" || frames_ms=""
  [[ -n $frames_ms && $frames_ms -ge 466 ]] || echo pacing
  [[ $(sed -n 's/^fds-after //p' <<<"$lines") == "$(sed -n 's/^fds-before //p' <<<"$lines")" ]] || echo fds
}

real_sink="$tmp/real/sink"
if ! build_sink "$tmp/real" "$repo/scripts/smoke/sink/sink.c" "the sink compiles"; then
  :
elif ! run_sink "$real_sink" "$tmp/real"; then
  fail "the sink listens on its socket: $(tail -n 3 -- "$tmp/real/sink.err")"
else
  broken="$(broken_rules "$tmp/real/probe.out")"
  for rule in probe globals input feedback configure ping release pacing fds; do
    if grep -qx "$rule" <<<"$broken"; then
      fail "the sink holds rule $rule; probe lines:"
      sed 's/^/        /' -- "$tmp/real/probe.out"
    else
      ok "the sink holds rule $rule"
    fi
  done
  [[ ! -e $sink_runtime/vgs-sink.part ]] && ok "the sink leaves no partial socket" || fail "the sink leaves its partial socket"
fi

# Refusals: invocation | want exit.
: >"$tmp/regular-file"
refusals=(
  "a relative socket|vgs-sink /dev/null|2"
  "a main device that is a regular file|$tmp/refused-socket $tmp/regular-file|2"
  "a main device that does not exist|$tmp/refused-socket $tmp/absent-device|2"
  "a character device that is no render node|$tmp/refused-socket /dev/null|1"
)
for row in "${refusals[@]}"; do
  IFS='|' read -r label words want <<<"$row"
  read -ra argv <<<"$words"
  status=0
  timeout -k 2 10 "$real_sink" "${argv[@]}" 2>/dev/null || status=$?
  if [[ $status == "$want" && ! -e $tmp/refused-socket ]]; then ok "the sink refuses $label"; else fail "the sink refuses $label: status=$status want $want"; fi
done

# Controls: label | rule that must go red | text in sink.c | its defect.
controls=(
  "a sink with no interval ping|ping|wl_resource_for_each(wm_base, &wm_bases) xdg_wm_base_send_ping(wm_base, wl_display_next_serial(display));|(void)wm_base;"
  "a sink that configures on every commit|configure|if (surface->toplevel && !surface->configured) {|if (surface->toplevel) {"
  "a sink that keeps the file descriptors it receives|fds|			close(args[index].h);|			(void)args[index].h;"
  "a sink that paces frames at 240 Hz|pacing|#define SINK_FRAME_NS (1000000000L / 60)|#define SINK_FRAME_NS (1000000000L / 240)"
  "a sink that never releases a buffer|release|			wl_buffer_send_release(surface->buffer);|			(void)surface->buffer;"
  "a sink that names its own filesystem's device|feedback|	main_device = device.st_rdev;|	main_device = device.st_dev;"
  "a sink whose format table names no explicit modifier|feedback|(struct format_entry){SINK_FORMATS[f], 0, modifiers[m]};|(struct format_entry){SINK_FORMATS[f], 0, 0x00ffffffffffffffULL};"
  "a sink that sends a pointer event|input|		child(resource, &wl_pointer_interface, args[0].n, NULL, NULL, NULL);|		wl_pointer_send_frame(child(resource, &wl_pointer_interface, args[0].n, NULL, NULL, NULL));"
)
index=0
for row in "${controls[@]}"; do
  IFS='|' read -r label rule old new <<<"$row"
  index=$((index + 1))
  dir="$tmp/control-$index"
  mkdir -- "$dir"
  if ! python3 - "$repo/scripts/smoke/sink/sink.c" "$old" "$new" "$dir/sink.c" <<'PY'
import pathlib, sys
source, old, new, out = sys.argv[1:]
text = pathlib.Path(source).read_text()
assert text.count(old) == 1, "mutation-source: " + old
changed = text.replace(old, new)
assert changed != text
pathlib.Path(out).write_text(changed)
PY
  then
    fail "control: $label could not be planted"
    continue
  fi
  build_sink "$dir" "$dir/sink.c" "control: $label could not be built" || continue
  if ! run_sink "$dir/sink" "$dir"; then
    fail "control: $label never listens: $(tail -n 3 -- "$dir/sink.err")"
    continue
  fi
  broken="$(broken_rules "$dir/probe.out")"
  if grep -qx "$rule" <<<"$broken"; then
    ok "control: $label breaks rule $rule"
  else
    fail "control: $label breaks rule $rule: broken=[${broken//$'\n'/,}]"
  fi
done

if [[ $failures -gt 0 ]]; then
  echo "test-smoke-sink: failed=$failures"
  exit 1
fi
echo "test-smoke-sink: ok"
