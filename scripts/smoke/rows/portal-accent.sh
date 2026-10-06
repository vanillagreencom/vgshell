# Portal Settings accent routing for libadwaita, run on the sandbox bus.
# Measured on host cachy, AMD Ryzen 9 9950X, 2026-10-06. This row adds no
# latency budget. It polls D-Bus name ownership every 100 ms and each portal
# Settings read is one gdbus round trip on the sandbox session bus.
# The sandbox tree ships no theme targets, so this row copies only the real
# accent-color target into that tree. It then runs the real `vgshell theme apply`
# with the sandbox bus and dconf service, which exercises the target hook.
# inputs: packaging/xdg-desktop-portal/hyprland-portals.conf themes/targets/accent-color/* themes/targets/color-scheme/* bin/vgshell bin/vgshell-theme-judge bin/lib/theme-* themes/catalog/gruvbox/* themes/catalog/flexoki-light/* shell/Commons/ThemeLogic.js shell/Commons/Tokens.js bin/lib/qml-library.js
set -euo pipefail

portal_bin=/usr/lib/xdg-desktop-portal
portal_gtk=/usr/lib/xdg-desktop-portal-gtk
portal_gnome=/usr/lib/xdg-desktop-portal-gnome
dconf_bin=/usr/lib/dconf-service
for pair in "xdg-desktop-portal:$portal_bin" "xdg-desktop-portal-gtk:$portal_gtk" "dconf-service:$dconf_bin"; do
  name="${pair%%:*}"; file="${pair#*:}"
  if [[ ! -x $file ]]; then
    not_measured portal-accent missing="$name"
    return 0
  fi
done
if [[ ! -x $portal_gnome ]]; then
  not_measured portal-accent missing=xdg-desktop-portal-gnome
  return 0
fi

portal_root="$sandbox/portal-accent"
mkdir -p -- "$portal_root/config/xdg-desktop-portal" "$portal_root/data/xdg-desktop-portal/portals" "$portal_root/bin"
cp -- "$repo/packaging/xdg-desktop-portal/hyprland-portals.conf" "$portal_root/config/xdg-desktop-portal/hyprland-portals.conf"
cp -- /usr/share/xdg-desktop-portal/portals/gtk.portal "$portal_root/data/xdg-desktop-portal/portals/gtk.portal"
if [[ -f /usr/share/xdg-desktop-portal/portals/hyprland.portal ]]; then
  cp -- /usr/share/xdg-desktop-portal/portals/hyprland.portal "$portal_root/data/xdg-desktop-portal/portals/hyprland.portal"
else
  not_measured portal-accent missing=hyprland.portal
  return 0
fi
if [[ -f /usr/share/xdg-desktop-portal/portals/gnome.portal ]]; then
  cp -- /usr/share/xdg-desktop-portal/portals/gnome.portal "$portal_root/data/xdg-desktop-portal/portals/gnome.portal"
else
  not_measured portal-accent missing=gnome.portal
  return 0
fi
ln -s -- "$(command -v sh)" "$portal_root/bin/sh"
ln -s -- "$(command -v cat)" "$portal_root/bin/cat"
ln -s -- "$(command -v gsettings)" "$portal_root/bin/gsettings"
ln -s -- "$(command -v node)" "$portal_root/bin/node"

mkdir -p -- "$repo/themes/targets/accent-color" "$repo/themes/targets/color-scheme"
cp -R -- "$source_repo/themes/targets/accent-color/." "$repo/themes/targets/accent-color/"
cp -R -- "$source_repo/themes/targets/color-scheme/." "$repo/themes/targets/color-scheme/"
mkdir -p -- "$home/.config/xdg-desktop-portal"
printf '%s\n' '[preferred]' 'default=hyprland;gtk' >"$home/.config/xdg-desktop-portal/portals.conf"

portal_env=("${shell_env[@]}" HOME="$home" XDG_CONFIG_HOME="$home/.config" XDG_DATA_HOME="$home/.local/share"
  XDG_STATE_HOME="$home/.local/state" XDG_CACHE_HOME="$home/.cache" XDG_CURRENT_DESKTOP=Hyprland
  GSETTINGS_BACKEND=dconf GSETTINGS_SCHEMA_DIR=/usr/share/glib-2.0/schemas WAYLAND_DISPLAY="$nested_socket"
  XDG_CONFIG_DIRS="$portal_root/config" XDG_DATA_DIRS="$portal_root/data:/usr/share" PATH="$portal_root/bin:$(dirname -- "$node_bin"):/usr/bin:/bin" TMPDIR="$sandbox")

name_owned() { "${portal_env[@]}" gdbus call --session --dest org.freedesktop.DBus --object-path /org/freedesktop/DBus --method org.freedesktop.DBus.NameHasOwner "$1" 2>>"$sandbox/ipc.log" | grep -q '(true,'; }
wait_name() { # BUS_NAME
  for _ in $(seq 1 50); do name_owned "$1" && { echo owned; return; }; sleep 0.1; done
  echo missing
}
portal_read() {
  "${portal_env[@]}" gdbus call --session --dest org.freedesktop.portal.Desktop --object-path /org/freedesktop/portal/desktop --method org.freedesktop.portal.Settings.ReadOne org.freedesktop.appearance accent-color 2>&1
}
portal_rgb() {
  portal_read | python3 -c 'import re, sys
text = sys.stdin.read()
m = re.search(r"<\(([-0-9.]+), ([-0-9.]+), ([-0-9.]+)\)>", text)
if not m:
    print("unreadable " + text.split("\n", 1)[0])
    raise SystemExit(1)
print("#" + "".join(f"{round(float(v) * 255):02x}" for v in m.groups()))'
}
portal_color_scheme() {
  "${portal_env[@]}" gdbus call --session --dest org.freedesktop.portal.Desktop --object-path /org/freedesktop/portal/desktop --method org.freedesktop.portal.Settings.ReadOne org.freedesktop.appearance color-scheme 2>&1 |
    python3 -c 'import re, sys
text = sys.stdin.read()
m = re.search(r"uint32 ([0-9]+)", text)
if not m:
    print("unreadable " + text.split("\n", 1)[0])
    raise SystemExit(1)
print(m.group(1))'
}
portal_read_failed() {
  local out status=0
  out="$(portal_read)" || status=$?
  if [[ $status -ne 0 && ( $out == *org.freedesktop.portal.Error.NotFound* || $out == *not-found* || $out == *not found* ) ]]; then echo failed; else printf 'status=%s %s
' "$status" "${out%%$'\n'*}"; fi
}
portal_stack_pids=()
start_portal_stack() { # LABEL CONFIG_DIR
  local label="$1" config_dir="$2"
  portal_stack_pids=()
  mkdir -p -- "$config_dir/xdg-desktop-portal"
  spawn "$portal_root/$label-dconf.log" "${portal_env[@]}" "$dconf_bin"
  portal_stack_pids+=("$spawn_pid")
  spawn "$portal_root/$label-gtk.log" "${portal_env[@]}" "$portal_gtk" -r
  portal_stack_pids+=("$spawn_pid")
  spawn "$portal_root/$label-gnome.log" "${portal_env[@]}" "$portal_gnome" -r
  portal_stack_pids+=("$spawn_pid")
  expect_poll "$label: gtk Settings backend owns its name" owned wait_name org.freedesktop.impl.portal.desktop.gtk
  expect_poll "$label: gnome Settings backend owns its name" owned wait_name org.freedesktop.impl.portal.desktop.gnome
  spawn "$portal_root/$label-desktop.log" "${portal_env[@]}" XDG_CONFIG_DIRS="$config_dir" "$portal_bin" -r
  portal_stack_pids+=("$spawn_pid")
  expect_poll "$label: xdg-desktop-portal owns its name" owned wait_name org.freedesktop.portal.Desktop
}
stop_spawned() { # PID
  local pid="$1"
  [[ $pid =~ ^[0-9]+$ ]] || return 0
  kill -- -"$pid" 2>/dev/null || true
  for _ in $(seq 1 50); do kill -0 "$pid" 2>/dev/null || return 0; sleep 0.1; done
  kill -KILL -- -"$pid" 2>/dev/null || true
}
stop_portal_stack() {
  local i
  for ((i = ${#portal_stack_pids[@]} - 1; i >= 0; i--)); do
    stop_spawned "${portal_stack_pids[i]}"
  done
  portal_stack_pids=()
}

empty_config="$portal_root/empty-config"
mkdir -p -- "$empty_config"
start_portal_stack control "$empty_config"
expect "control: gtk-only Settings route has no accent-color" failed portal_read_failed
stop_portal_stack
expect_poll "control: xdg-desktop-portal releases its bus name" missing wait_name org.freedesktop.portal.Desktop
expect_poll "control: gtk Settings backend releases its bus name" missing wait_name org.freedesktop.impl.portal.desktop.gtk
expect_poll "control: gnome Settings backend releases its bus name" missing wait_name org.freedesktop.impl.portal.desktop.gnome

start_portal_stack routed "$portal_root/config"
expect_poll "routed portal starts before theme assertions" owned wait_name org.freedesktop.portal.Desktop
apply_theme() { # NAME
  "${portal_env[@]}" "$repo/bin/vgshell" theme apply --json "$1" >/dev/null
}
apply_theme_and_read() { # NAME VALUE
  apply_theme "$1" || return
  case "$2" in
    accent) portal_rgb ;;
    color-scheme) portal_color_scheme ;;
  esac
}
apply_vgs_default() {
  "${portal_env[@]}" "$repo/bin/vgshell" theme apply vgs | tail -n 1
}
expect "the sandbox dark theme sets gruvbox through the real accent target" "#3a944a" apply_theme_and_read gruvbox accent
expect "the merged Settings portal reads gruvbox as prefer-dark" "1" apply_theme_and_read gruvbox color-scheme
expect "the sandbox light theme sets flexoki-light through the real accent target" "#3584e4" apply_theme_and_read flexoki-light accent
expect "the merged Settings portal reads flexoki-light as prefer-light" "2" apply_theme_and_read flexoki-light color-scheme
expect "the portal accent row restores vgs before later rows" "ok theme=vgs state=applied shell=applied" apply_vgs_default
stop_portal_stack
expect_poll "routed portal releases its bus name" missing wait_name org.freedesktop.portal.Desktop
expect_poll "routed gtk Settings backend releases its bus name" missing wait_name org.freedesktop.impl.portal.desktop.gtk
expect_poll "routed gnome Settings backend releases its bus name" missing wait_name org.freedesktop.impl.portal.desktop.gnome
rm -rf -- "${repo:?}/themes/targets/accent-color" "${repo:?}/themes/targets/color-scheme"
rm -rf -- "$home/.config/xdg-desktop-portal"
